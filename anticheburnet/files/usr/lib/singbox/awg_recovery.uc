#!/usr/bin/ucode
let fs = require("fs");

function quote(value) { return "'" + replace("" + value, /'/g, "'\\''") + "'"; }
function output(command) {
    let pipe = fs.popen(command + " 2>/dev/null", "r");
    if (!pipe) return null;
    let value = pipe.read("all"), status = pipe.close();
    return status == 0 ? value : null;
}
function instances() {
    let value = output("ubus -t 10 call service list '{\"name\":\"anticheburnet-awg-subscriptions\"}'");
    if (value == null) return null;
    try {
        let service = json(value)["anticheburnet-awg-subscriptions"];
        return service == null ? {} : (service.instances || {});
    }
    catch (error) { return null; }
}
function identity(pid, iface) {
    if (!match("" + pid, /^[0-9]+$/)) return "";
    let base = "/proc/" + pid;
    if (fs.readfile(base + "/cmdline") != "amneziawg-go" + chr(0) + "-f" + chr(0) + iface + chr(0) ||
        fs.readlink(base + "/exe") != "/usr/bin/amneziawg-go (deleted)" ||
        !match(fs.readfile(base + "/status") || "", /\nPPid:[ \t]+1\n/)) return "";
    // stat comm can contain spaces. Field 22 follows the final closing paren.
    let stat = match(fs.readfile(base + "/stat") || "", /^.*\) (.*)$/);
    let fields = stat == null ? [] : split(trim(stat[1]), /[ \t]+/);
    return length(fields) > 19 ? fields[19] : "";
}
function candidate(iface) {
    let flags = trim(fs.readfile("/sys/class/net/" + iface + "/flags") || "");
    if (!match(iface, /^acawg([1-9]|[12][0-9]|3[0-2])$/) ||
        !match(flags, /^0x[0-9a-fA-F]+$/) || (int(flags, 16) & 1) != 0 ||
        trim(fs.readfile("/sys/class/net/" + iface + "/operstate") || "") != "down" ||
        fs.stat("/var/run/anticheburnet/awg-" + iface + ".ready")) return null;
    let found = null;
    for (let path in fs.glob("/proc/[0-9]*/cmdline")) {
        let pid = split(path, "/")[2], stamp = identity(pid, iface);
        if (stamp == "") continue;
        if (found != null) return null;
        found = { pid, stamp, interface: iface };
    }
    return found;
}
function has_orphans() {
    let candidates = [];
    for (let i = 1; i <= 32; i++)
        if (candidate("acawg" + i) != null) push(candidates, "acawg" + i);
    if (!length(candidates)) return false;
    let registered = instances();
    if (registered == null) return false;
    for (let iface in candidates)
        if (registered[iface] == null) return true;
    return false;
}
function recover(profile) {
    let iface = profile.interface, table = profile.table;
    if (!match(iface || "", /^acawg([1-9]|[12][0-9]|3[0-2])$/) ||
        table != 311 + int(substr(iface, 5))) return false;
    let registered = instances(), orphan = candidate(iface);
    if (registered == null || registered[iface] != null || orphan == null) return false;
    if (output("ip -o address show dev " + quote(iface)) != "") return false;
    for (let family in [ "-4", "-6" ]) {
        // ip returns 2 for a nonexistent (empty) table; other failures fail closed.
        let routes = output("ip " + family + " route show table " + table + "; rc=$?; [ $rc -eq 0 ] || [ $rc -eq 2 ]");
        let rules = output("ip " + family + " rule show");
        if (routes != "" || rules == null ||
            match(rules, regexp("(^|[ \\t])oif " + iface + "([ \\t]|$)")) ||
            match(rules, regexp("lookup " + table + "([ \\t\\n]|$)"))) return false;
    }
    // Recheck registry and PID birth time immediately before the precise signal.
    registered = instances();
    if (registered == null || registered[iface] != null || identity(orphan.pid, iface) != orphan.stamp) return false;
    if (system("kill -TERM " + orphan.pid + " 2>/dev/null") != 0) return false;
    for (let i = 0; i < 100; i++) {
        if (identity(orphan.pid, iface) == "" && !fs.stat("/sys/class/net/" + iface) &&
            !fs.stat("/var/run/amneziawg/" + iface + ".sock")) return true;
        sleep(100);
    }
    return false;
}
function schedule() {
    if (!has_orphans()) return true;
    let payload = { name: "anticheburnet-upgrade-recovery", instances: { recover: {
        command: [ "ucode", "-L", "/usr/lib/anticheburnet", "/usr/lib/anticheburnet/singbox/awg_recovery.uc", "after-upgrade" ],
        stderr: true
    } } };
    return system("ubus -t 10 call service add " + quote(sprintf("%J", payload)) + " >/dev/null 2>&1") == 0;
}
function after_upgrade() {
    // An old updater skips restart if the service was already broken. Wait for
    // its transaction to finish before starting through the newly installed code.
    for (let i = 0; i < 600; i++) {
        sleep(1000);
        let pid = trim(fs.readfile("/var/run/anticheburnet/component-action.lock/pid") || "");
        if (match(pid, /^[0-9]+$/) && fs.stat("/proc/" + pid)) continue;
        let managers = output("pidof apk opkg");
        if (managers != null && trim(managers) != "") continue;
        if (system("/etc/init.d/anticheburnet status >/dev/null 2>&1") == 0) return true;
        if (!has_orphans()) return true;
        return system("/etc/init.d/anticheburnet start") == 0;
    }
    warn("Timed out waiting for the package transaction before AWG recovery\n");
    return false;
}
if (sourcepath(1) != null && sourcepath(1) != "") return { candidate, has_orphans, recover, schedule, after_upgrade };
if (ARGV[0] == "after-upgrade") exit(after_upgrade() ? 0 : 1);
die("Usage: awg_recovery.uc after-upgrade\n");
