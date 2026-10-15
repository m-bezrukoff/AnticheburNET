#!/usr/bin/ucode
let fs = require("fs");
let awg = require("core.awg");
const SERVICE = "/etc/init.d/anticheburnet-awg-subscriptions";
const STATE = "/var/run/anticheburnet/awg-subscriptions.json";

function write_private(path, text) {
    let file = fs.open(path, "w", 0600);
    if (!file) return false;
    if (!fs.chmod(path, 0600)) { file.close(); return false; }
    let written = file.write(text);
    let closed = file.close();
    return written == length(text) && closed != null;
}

function prepare_outbounds(outbounds) {
    let profiles = [];
    let interfaces = {};
    for (let outbound in outbounds) {
        if (outbound.__awg_config == null) continue;
        if (outbound.type != "direct" || outbound.detour)
            die("AWG subscription profiles require native direct egress\n");
        let config = outbound.__awg_config;
        awg.prepare_text(config);
        let iface = interfaces[config];
        if (!iface) {
            if (length(profiles) >= 32) die("At most 32 distinct native AWG profiles are supported\n");
            let index = length(profiles) + 1;
            iface = "acawg" + index;
            interfaces[config] = iface;
            push(profiles, { interface: iface, table: 311 + index, config });
        }
        // Only sockets bound to this interface use its private routing table.
        outbound.bind_interface = iface;
        delete outbound.__awg_config;
    }
    return profiles;
}

function profiles(path) {
    let text = fs.readfile(path);
    if (text == null) return [];
    let value = json(text);
    if (type(value) != "array" || length(value) > 32) die("Invalid native AWG manifest\n");
    for (let i = 0; i < length(value); i++) {
        let profile = value[i];
        // Vacant slots keep surviving interfaces and runner indices stable.
        if (profile == null) continue;
        if (type(profile) != "object" || profile.interface != "acawg" + (i + 1) || profile.table != 312 + i)
            die("Invalid native AWG instance\n");
        awg.prepare_text(profile.config);
    }
    return value;
}

function ready(items) {
    for (let profile in items) {
        if (profile == null) continue;
        if (!fs.stat("/var/run/anticheburnet/awg-" + profile.interface + ".ready") ||
            !fs.stat("/var/run/amneziawg/" + profile.interface + ".sock")) return false;
    }
    return true;
}

function store_manifest(path, items) {
    let text = sprintf("%J\n", items);
    if (fs.readfile(path) == text) return true;
    let temporary = path + ".next";
    if (!write_private(temporary, text)) { fs.unlink(temporary); return false; }
    if (fs.rename(temporary, path)) return true;
    fs.unlink(temporary);
    return false;
}

function service_call(method, value) {
    let argument = replace(sprintf("%J", value), /'/g, "'\\''");
    return system("ubus -t 10 call service " + method + " '" + argument + "' >/dev/null 2>&1") == 0;
}

function service_instances() {
    let pipe = fs.popen("ubus -t 10 call service list '{\"name\":\"anticheburnet-awg-subscriptions\"}'", "r");
    if (!pipe) return null;
    let text = pipe.read("all");
    if (pipe.close() != 0) return null;
    try {
        let service = json(text)["anticheburnet-awg-subscriptions"];
        return service == null ? {} : (service.instances || {});
    }
    catch (error) { return null; }
}

function wait_ready(items) {
    for (let i = 0; i < 100; i++) {
        if (ready(items)) return true;
        sleep(100);
    }
    return false;
}

function put_profile(items, index, profile) {
    while (length(items) <= index) push(items, null);
    items[index] = profile;
}

// Reserve old slots until the provider confirms the new graph. A rotated profile
// therefore starts beside its predecessor instead of disrupting live traffic.
function plan_update(current, candidate, outbounds) {
    let next = [], staged = [], added = [], remap = {};
    for (let profile in current) push(staged, profile);
    for (let profile in candidate) {
        if (profile == null) continue;
        let slot = -1;
        for (let i = 0; i < length(current); i++)
            if (current[i] != null && current[i].config == profile.config) { slot = i; break; }
        if (slot < 0) {
            for (let i = 0; i < 32; i++)
                if (staged[i] == null) { slot = i; break; }
            if (slot < 0) die("No free native AWG slot for a safe subscription update\n");
            let item = { interface: "acawg" + (slot + 1), table: 312 + slot, config: profile.config };
            put_profile(staged, slot, item);
            push(added, item);
        }
        put_profile(next, slot, staged[slot]);
        remap[profile.interface] = staged[slot].interface;
    }
    for (let outbound in outbounds)
        if (outbound.type == "direct" && remap[outbound.bind_interface] != null)
            outbound.bind_interface = remap[outbound.bind_interface];
    return { current, next, staged, added };
}

function remove_instances(items) {
    if (!length(items)) return true;
    let instances = service_instances();
    if (instances == null) return false;
    let ok = true;
    for (let profile in items)
        if (profile != null && instances[profile.interface] != null &&
            !service_call("delete", { name: "anticheburnet-awg-subscriptions", instance: profile.interface }))
            ok = false;
    // procd terminates runners asynchronously. Do not reuse a slot until its
    // cleanup has removed both readiness and the userspace device socket.
    for (let i = 0; i < 120; i++) {
        let pending = false;
        for (let profile in items)
            if (profile != null && (fs.stat("/var/run/anticheburnet/awg-" + profile.interface + ".ready") ||
                fs.stat("/var/run/amneziawg/" + profile.interface + ".sock"))) pending = true;
        if (!pending) return ok;
        sleep(100);
    }
    return false;
}

function rollback_update(path, plan) {
    if (!length(plan.staged)) return true;
    if (!remove_instances(plan.added)) return false;
    return store_manifest(path, plan.current) && store_manifest(STATE, plan.current);
}

function begin_update(path, plan) {
    if (!length(plan.staged)) return true;
    let registered = service_instances();
    if (registered == null) return false;
    if (length(plan.added) && (!fs.stat(SERVICE) || !fs.stat("/usr/bin/amneziawg-go") || !fs.stat("/usr/bin/awg")))
        return false;
    for (let profile in plan.added)
        if (registered[profile.interface] != null || fs.stat("/var/run/anticheburnet/awg-" + profile.interface + ".ready") ||
            fs.stat("/var/run/amneziawg/" + profile.interface + ".sock")) return false;
    if (!store_manifest(path, plan.staged)) return false;
    let started = [];
    for (let profile in plan.next) {
        if (profile == null || registered[profile.interface] != null) continue;
        let instances = {};
        instances[profile.interface] = {
            command: [ "/usr/bin/anticheburnet-awg-subscription-run", profile.interface, path,
                "" + profile.table, "" + (profile.table - 311) ],
            file: [ path ], respawn: [ "3600", "5", "5" ], term_timeout: 10, stderr: true
        };
        // A retry may recover a reserved instance after an interrupted prepare.
        // Keep recovered old instances on rollback: the old graph can use them.
        if (plan.current[profile.table - 312] == null) push(started, profile);
        if (!service_call("add", { name: "anticheburnet-awg-subscriptions", script: SERVICE, instances })) {
            if (remove_instances(started)) {
                store_manifest(path, plan.current);
                store_manifest(STATE, plan.current);
            }
            return false;
        }
    }
    if (wait_ready(plan.next) && store_manifest(STATE, plan.staged)) return true;
    rollback_update(path, plan);
    return false;
}

function commit_update(path, plan) {
    if (!length(plan.staged)) return true;
    let removed = [];
    for (let i = 0; i < length(plan.current); i++)
        if (plan.current[i] != null && plan.next[i] == null) push(removed, plan.current[i]);
    if (!remove_instances(removed)) return false;
    return store_manifest(path, plan.next) && store_manifest(STATE, plan.next);
}

function stop() {
    if (fs.stat(SERVICE) && system(SERVICE + " stop") != 0) return false;
    fs.unlink(STATE);
    return true;
}

function sync(path) {
    let items = profiles(path);
    if (!length(items)) return stop();
    if (!fs.stat(SERVICE) || !fs.stat("/usr/bin/amneziawg-go") || !fs.stat("/usr/bin/awg"))
        die("AWG profiles require the AnticheburNET AmneziaWG component\n");
    let text = fs.readfile(path);
    if (fs.readfile(STATE) == text && ready(items)) return true;
    if (system(SERVICE + " restart") != 0) { stop(); return false; }
    for (let i = 0; i < 100; i++) {
        if (ready(items)) {
            if (!write_private(STATE, text)) { stop(); return false; }
            return true;
        }
        sleep(100);
    }
    stop();
    warn("Native AWG subscription interfaces did not become ready\n");
    return false;
}

if (sourcepath(1) != null && sourcepath(1) != "") return {
    prepare_outbounds, profiles, write_private, sync, stop,
    plan_update, begin_update, commit_update, rollback_update
};
let mode = ARGV[0];
if (mode == "plan") {
    let items = profiles(ARGV[1]);
    for (let i = 0; i < length(items); i++)
        if (items[i] != null) print(items[i].interface, "\t", items[i].table, "\t", i + 1, "\n");
}
else if (mode == "extract") {
    let items = profiles(ARGV[1]);
    if (!match(ARGV[2] || "", /^[0-9]+$/)) die("Invalid AWG profile index\n");
    let index = int(ARGV[2]) - 1;
    if (index < 0 || index >= length(items) || items[index] == null) die("Invalid AWG profile index\n");
    if (!write_private(ARGV[3], items[index].config))
        die("Unable to extract private AWG profile\n");
}
else if (mode == "sync") exit(sync(ARGV[1]) ? 0 : 1);
else if (mode == "stop") exit(stop() ? 0 : 1);
else die("Usage: singbox/awg.uc plan MANIFEST | extract MANIFEST INDEX OUTPUT | sync MANIFEST | stop\n");
