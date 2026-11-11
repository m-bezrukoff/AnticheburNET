#!/usr/bin/ucode
let fs = require("fs");
let native = require("core.xray");
let private_files = require("singbox.awg");
const SERVICE = "anticheburnet-xray-profiles";
const DIRECTORY = getenv("ANTICHEBURNET_XRAY_PROFILE_DIR") || "/var/run/anticheburnet/xray-profiles";
const STATE = DIRECTORY + "/state.json";
const BINARY = getenv("ANTICHEBURNET_XRAY_BIN") || "/usr/bin/xray";
const ASSETS = getenv("ANTICHEBURNET_XRAY_ASSETS") || "/usr/bin/anticheburnet-xray-assets";

function quote(value) { return "'" + replace("" + value, /'/g, "'\\''") + "'"; }
function capture(args) {
    let escaped = []; for (let arg in args) push(escaped, quote(arg));
    let pipe = fs.popen(join(" ", escaped) + " 2>/dev/null", "r");
    if (!pipe) return null;
    let text = pipe.read("all");
    return pipe.close() == 0 ? text : null;
}
function service_call(method, value) {
    return system("ubus -t 10 call service " + method + " " + quote(sprintf("%J", value)) + " >/dev/null 2>&1") == 0;
}
function config_path(profile) { return DIRECTORY + "/" + profile.port + ".json"; }
function profiles(path) {
    let text = fs.readfile(path);
    if (text == null) return [];
    let items = json(text);
    if (type(items) != "array" || length(items) > native.MAX_PROFILES) die("Invalid native Xray manifest\n");
    for (let i = 0; i < length(items); i++) {
        if (type(items[i]) != "object" || items[i].port != native.PORT_BASE + i || native.config_error(items[i].config) != "")
            die("Invalid native Xray instance\n");
        items[i].config = native.prepare(items[i].config, items[i].port);
    }
    return items;
}
function payload(items, assets) {
    let instances = {};
    for (let item in items) instances["xray" + item.port] = {
        command: [ BINARY, "run", "-config", config_path(item) ],
        env: { XRAY_LOCATION_ASSET: assets },
        file: [ config_path(item) ], respawn: [ 3600, 5, 5 ], term_timeout: 10,
        stderr: true, limits: { nofile: "65536 65536" }
    };
    return { name: SERVICE, instances };
}
function wait_running(items) {
    let stable = 0, previous_pids = "";
    for (let attempt = 0; attempt < 50; attempt++) {
        let text = capture([ "ubus", "-t", "2", "call", "service", "list", sprintf("%J", { name: SERVICE }) ]);
        let value = null;
        try { value = json(text); } catch (error) {}
        let instances = value != null && value[SERVICE] != null ? value[SERVICE].instances : null;
        let ready = instances != null;
        let pids = [];
        for (let item in items) {
            let instance = instances != null ? instances["xray" + item.port] : null;
            if (instance == null || !instance.running || int(instance.pid || 0) <= 0) ready = false;
            push(pids, instance != null ? instance.pid : 0);
        }
        let signature = sprintf("%J", pids);
        stable = ready ? (signature == previous_pids ? stable + 1 : 1) : 0;
        previous_pids = signature;
        if (stable >= 3) return true;
        sleep(100);
    }
    return false;
}
function write_configs(items) {
    for (let item in items)
        if (!private_files.write_private(config_path(item), sprintf("%J\n", item.config))) return false;
    return true;
}
function store_manifest(items) {
    let temporary = STATE + ".next";
    if (!private_files.write_private(temporary, sprintf("%J\n", items))) return false;
    if (fs.rename(temporary, STATE)) return true;
    fs.unlink(temporary);
    return false;
}
function stop() {
    if (!fs.stat(STATE)) return true;
    if (!service_call("delete", { name: SERVICE })) return false;
    // Cleanup uses only the fixed private filenames owned by this service.
    for (let i = 0; i < native.MAX_PROFILES; i++) fs.unlink(config_path({ port: native.PORT_BASE + i }));
    return fs.unlink(STATE);
}
function prepare_profiles(candidate) {
    if (!length(candidate)) return "";
    let version = capture([ BINARY, "version" ]);
    if (version == null || match(version, /^Xray 26[.]11[.]9[ \r\n]/) == null) {
        warn("Native Xray profiles require the matching 26.11.9 component. Update the complete release in Components.\n");
        return null;
    }
    let assets = capture([ ASSETS ]);
    if (assets == null || trim(assets) == "") return null;
    assets = trim(assets);
    let parent = fs.dirname(DIRECTORY);
    if (!fs.stat(parent) && !fs.mkdir(parent, 0700)) return null;
    if (!fs.stat(DIRECTORY) && !fs.mkdir(DIRECTORY, 0700)) return null;
    if (!fs.chmod(DIRECTORY, 0700)) return null;
    // Validate all profiles before replacing any running native instance.
    for (let item in candidate) {
        let temporary = config_path(item) + ".candidate";
        if (!private_files.write_private(temporary, sprintf("%J\n", item.config))) return null;
        let result = capture([ "env", "XRAY_LOCATION_ASSET=" + assets, BINARY, "run", "-test", "-config", temporary ]);
        fs.unlink(temporary);
        if (result == null) { warn("Native Xray configuration was rejected\n"); return null; }
    }
    return assets;
}
function check_uci() {
    let uci = require("core.uci");
    let outbounds = native.configured_outbounds(uci.section_objects("anticheburnet", "section"));
    let candidate = native.prepare_outbounds(outbounds);
    return prepare_profiles(candidate) != null;
}
function check_profiles(path) { return prepare_profiles(profiles(path)) != null; }
function sync(path) {
    let candidate = profiles(path);
    if (!length(candidate)) return stop();
    let assets = prepare_profiles(candidate);
    if (assets == null) return false;
    let previous = profiles(STATE);
    if (sprintf("%J", previous) == sprintf("%J", candidate) && wait_running(candidate)) return true;
    if (!write_configs(candidate)) { write_configs(previous); return false; }
    if (!service_call("set", payload(candidate, assets)) || !wait_running(candidate) ||
        !store_manifest(candidate)) {
        let restored = write_configs(previous);
        if (length(previous)) restored = service_call("set", payload(previous, assets)) && wait_running(previous) && restored;
        else restored = service_call("delete", { name: SERVICE }) && restored;
        warn(restored ? "Native Xray startup failed; previous profiles were restored\n" :
            "Native Xray startup failed and rollback could not be confirmed\n");
        return false;
    }
    for (let item in previous)
        if (item.port >= native.PORT_BASE + length(candidate)) fs.unlink(config_path(item));
    return true;
}

if (sourcepath(1) != null && sourcepath(1) != "") return { profiles, payload, sync, stop, check_uci, check_profiles };
if (ARGV[0] == "check-uci") exit(check_uci() ? 0 : 1);
if (ARGV[0] == "stop") exit(stop() ? 0 : 1);
if (ARGV[0] == "sync") exit(sync(ARGV[1]) ? 0 : 1);
die("Usage: singbox/xray.uc sync MANIFEST|stop\n");
