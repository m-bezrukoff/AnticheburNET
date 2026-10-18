// A private, loopback-only download proxy also works before the main service
// starts, and uses the newly selected connection rather than an old listener.
let fs = require("fs");
let common = require("core.common");
let constants = require("singbox.constants");
let dns = require("singbox.dns");
let reality = require("singbox.reality");
let awg = require("singbox.awg");
const AWG_STATE = "/var/run/anticheburnet/awg-subscriptions.json";

function quote(value) { return "'" + replace(value, /'/g, "'\\''") + "'"; }

function proxy_config(config, settings, section, version) {
    let target = constants.outbound_tag(section), available = {}, needed = {}, queue = [ target, constants.DIRECT_OUTBOUND_TAG ];
    for (let outbound in config.outbounds) available[outbound.tag] = outbound;
    while (length(queue)) {
        let tag = shift(queue);
        if (needed[tag]) continue;
        let outbound = available[tag];
        if (outbound == null) die("Geodata download connection is unavailable\n");
        needed[tag] = true;
        if (outbound.detour) push(queue, outbound.detour);
        for (let member in outbound.outbounds || []) push(queue, member);
    }
    let outbounds = [];
    for (let outbound in config.outbounds)
        if (needed[outbound.tag]) push(outbounds, json(sprintf("%J", outbound)));
    let bootstrap = dns.bootstrap_config(settings, {});
    if (bootstrap.unsupported) die("Invalid bootstrap DNS for geodata proxy\n");
    for (let outbound in outbounds)
        if (outbound.domain_resolver != null) outbound.domain_resolver = bootstrap.tag;
    reality.prepare_outbounds(outbounds, version);
    let profiles = awg.prepare_outbounds(outbounds);
    let route = { final: target, default_domain_resolver: bootstrap.tag, default_mark: constants.OUTBOUND_MARK,
        auto_detect_interface: config.route.auto_detect_interface };
    if (config.route.default_interface) route.default_interface = config.route.default_interface;
    return { profiles, config: common.strip_internal_fields({ log: { level: "info", timestamp: false, disabled: false },
        dns: { servers: [ bootstrap ], final: bootstrap.tag }, route, outbounds,
        inbounds: [ { type: "mixed", tag: "geodata-download", listen: "127.0.0.1", listen_port: 0 } ] }) };
}

function execute(command, proxy_address, config, settings, section, directory, version, runner) {
    let prepared = proxy_config(config, settings, section, version);
    let stamp = clock(), path = directory + "/download-proxy-" + stamp[0] + "-" + stamp[1];
    let manifest = path + ".awg.json", plan = null;
    if (length(prepared.profiles)) {
        plan = awg.plan_update(awg.profiles(AWG_STATE), prepared.profiles, prepared.config.outbounds);
        if (!awg.begin_update(manifest, plan)) die("Unable to prepare native AWG for geodata download\n");
    }
    if (!awg.write_private(path + ".json", sprintf("%J\n", prepared.config))) {
        if (plan != null && !awg.rollback_update(manifest, plan))
            die("Unable to restore native AWG state after preparing geodata proxy\n");
        fs.unlink(manifest);
        die("Unable to prepare private geodata download proxy\n");
    }
    let download = replace(command, "--proxy " + quote(proxy_address), "--proxy \"http://127.0.0.1:$geodata_port\"");
    let binary = getenv("ANTICHEBURNET_SING_BOX_BIN") || "/usr/bin/sing-box";
    let script = "umask 077\n" + quote(binary) + " run -c " + quote(path + ".json") + " >" + quote(path + ".log") + " 2>&1 &\n" +
        "geodata_pid=$!\ntrap 'kill \"$geodata_pid\" 2>/dev/null; wait \"$geodata_pid\" 2>/dev/null' EXIT\n" +
        "trap 'exit 1' HUP INT TERM\ngeodata_port=\ngeodata_wait=0\n" +
        "while [ \"$geodata_wait\" -lt 100 ]; do\n" +
        "kill -0 \"$geodata_pid\" 2>/dev/null || exit 1\n" +
        "geodata_port=$(sed -n 's/.*tcp server started at 127[.]0[.]0[.]1:\\([0-9][0-9]*\\).*/\\1/p' " + quote(path + ".log") + " | head -n 1)\n" +
        "if [ -n \"$geodata_port\" ] && grep -q 'sing-box started' " + quote(path + ".log") + "; then break; fi\n" +
        "sleep 0.1\ngeodata_wait=$((geodata_wait + 1))\ndone\n" +
        "case \"$geodata_port\" in ''|*[!0-9]*) exit 1;; esac\n" +
        "[ \"$geodata_wait\" -lt 100 ] || exit 1\n" + download;
    let run = type(runner) == "function" ? runner : system;
    let result = run("sh -c " + quote(script));
    let restored = plan == null || awg.rollback_update(manifest, plan);
    fs.unlink(path + ".json"); fs.unlink(path + ".log");
    if (!restored) die("Unable to restore native AWG state after geodata download\n");
    fs.unlink(manifest);
    return result;
}

return { proxy_config, execute };
