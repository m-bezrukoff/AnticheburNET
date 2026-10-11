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
        if (type(profile) != "object" || profile.interface != "acawg" + (i + 1) || profile.table != 312 + i)
            die("Invalid native AWG instance\n");
        awg.prepare_text(profile.config);
    }
    return value;
}

function ready(items) {
    for (let profile in items) {
        if (!fs.stat("/var/run/anticheburnet/awg-" + profile.interface + ".ready") ||
            !fs.stat("/var/run/amneziawg/" + profile.interface + ".sock")) return false;
    }
    return true;
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

if (sourcepath(1) != null && sourcepath(1) != "") return { prepare_outbounds, profiles, write_private, sync, stop };
let mode = ARGV[0];
if (mode == "plan") {
    let items = profiles(ARGV[1]);
    for (let i = 0; i < length(items); i++)
        print(items[i].interface, "\t", items[i].table, "\t", i + 1, "\n");
}
else if (mode == "extract") {
    let items = profiles(ARGV[1]);
    if (!match(ARGV[2] || "", /^[0-9]+$/)) die("Invalid AWG profile index\n");
    let index = int(ARGV[2]) - 1;
    if (index < 0 || index >= length(items)) die("Invalid AWG profile index\n");
    if (!write_private(ARGV[3], items[index].config))
        die("Unable to extract private AWG profile\n");
}
else if (mode == "sync") exit(sync(ARGV[1]) ? 0 : 1);
else if (mode == "stop") exit(stop() ? 0 : 1);
else die("Usage: singbox/awg.uc plan MANIFEST | extract MANIFEST INDEX OUTPUT | sync MANIFEST | stop\n");
