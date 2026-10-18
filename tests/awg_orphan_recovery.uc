let fs = require("fs"), recovery = require("singbox.awg_recovery");
function check(ok, message) { if (!ok) die(message + "\n"); }
let files, links, registered, executable, parent, routes, rules, addresses, killed, alive, ticks, lock_waits, managers;
let commands = [], profile = { interface: "acawg1", table: 312 }, reads = 0, race = "", registry_reads = 0, service_running = false;
function reset() {
    files = {}; links = {}; registered = {}; executable = "/usr/bin/amneziawg-go (deleted)";
    parent = 1; routes = ""; rules = ""; addresses = ""; killed = false; alive = true; ticks = 100; lock_waits = 0; managers = 0;
    files["/sys/class/net/acawg1/operstate"] = "down\n";
    files["/sys/class/net/acawg1/flags"] = "0x1090\n";
    files["/var/run/amneziawg/acawg1.sock"] = "socket";
    commands = [];
    reads = 0; race = ""; registry_reads = 0;
    service_running = false;
}
fs.glob = function(pattern) { return alive ? [ "/proc/123/cmdline" ] : []; };
fs.readfile = function(path) {
    if (path == "/proc/123/cmdline") return alive ? "amneziawg-go" + chr(0) + "-f" + chr(0) + "acawg1" + chr(0) : null;
    if (path == "/proc/123/status") return "Name:\tamneziawg-go\nPPid:\t" + parent + "\n";
    if (path == "/proc/123/stat") {
        reads++;
        let fields = []; for (let i = 0; i < 20; i++) push(fields, "0"); fields[19] = "" + ticks;
        if (race == "pid" && reads > 1) fields[19] = "101";
        return "123 (amneziawg-go) " + join(" ", fields);
    }
    if (path == "/var/run/anticheburnet/component-action.lock/pid" && lock_waits > 0) return "987\n";
    return files[path];
};
fs.readlink = function(path) { return executable; };
fs.stat = function(path) {
    if (path == "/proc/987" && lock_waits > 0) { lock_waits--; return {}; }
    if (path == "/sys/class/net/acawg1") return alive ? {} : null;
    return files[path] != null ? {} : null;
};
fs.popen = function(command, mode) {
    let result = "", status = 0;
    if (index(command, "service list") >= 0) {
        registry_reads++;
        if (race == "registry" && registry_reads > 1) registered.acawg1 = { running: true };
        if (race == "uncertain") status = 1;
        result = sprintf("%J", { "anticheburnet-awg-subscriptions": { instances: registered } });
    }
    else if (index(command, "address show") >= 0) result = addresses;
    else if (index(command, "route show") >= 0) result = routes;
    else if (index(command, "rule show") >= 0) result = rules;
    else if (index(command, "pidof") >= 0) { if (managers > 0) { result = "456\n"; managers--; } else status = 1; }
    else die("Unexpected recovery read\n");
    return { read: function(mode) { return result; }, close: function() { return status; } };
};
system = function(command) {
    push(commands, command);
    if (index(command, "kill -TERM ") == 0) {
        check(command == "kill -TERM 123 2>/dev/null", "Recovery must signal only the verified PID");
        killed = true; alive = false; delete files["/var/run/amneziawg/acawg1.sock"]; return 0;
    }
    if (index(command, "service add") >= 0) return 0;
    if (index(command, "anticheburnet status") >= 0) return service_running ? 0 : 1;
    if (command == "/etc/init.d/anticheburnet start") {
        check(lock_waits == 0 && managers == 0, "Recovery started before the update transaction finished");
        service_running = true; return 0;
    }
    die("Unexpected recovery mutation\n");
};
sleep = function(ms) {};
reset();
check(recovery.has_orphans() && recovery.recover(profile) && killed, "Exact inactive pre-upgrade orphan must recover");
for (let scenario in [ "managed", "ready", "up", "admin_up", "address", "route", "rule", "current_binary", "parent" ]) {
    reset();
    if (scenario == "managed") registered.acawg1 = { running: true };
    if (scenario == "ready") files["/var/run/anticheburnet/awg-acawg1.ready"] = "";
    if (scenario == "up") files["/sys/class/net/acawg1/operstate"] = "up\n";
    if (scenario == "admin_up") files["/sys/class/net/acawg1/flags"] = "0x1091\n";
    if (scenario == "address") addresses = "10.0.0.2/32\n";
    if (scenario == "route") routes = "default dev acawg1\n";
    if (scenario == "rule") rules = "10400: from all oif acawg1 lookup 312\n";
    if (scenario == "current_binary") executable = "/usr/bin/amneziawg-go";
    if (scenario == "parent") parent = 555;
    check(!recovery.recover(profile) && !killed, "Recovery must preserve unsafe candidate: " + scenario);
}
reset();
check(!recovery.recover({ interface: "awg0", table: 311 }) && !killed, "Manual AWG must never be recovered as a subscription orphan");
for (let scenario in [ "pid", "registry", "uncertain" ]) {
    reset(); race = scenario;
    check(!recovery.recover(profile) && !killed, "Changed or uncertain ownership must refuse a signal: " + scenario);
}
reset();
check(recovery.schedule() && length(commands) == 1 && index(commands[0], "after-upgrade") >= 0 && !killed,
    "Deferred package hook must queue recovery without starting inside the package transaction");
reset(); alive = false;
check(recovery.schedule() && !length(commands), "Intentionally stopped services without upgrade orphans must stay stopped");
reset(); lock_waits = 2; managers = 1;
check(recovery.after_upgrade() && service_running && index(commands, "/etc/init.d/anticheburnet start") >= 0,
    "Old updater must hand off failed-start recovery after releasing its lock");
print("AWG upgrade orphan ownership, active traffic guards, deferred restart and stopped-service checks passed\n");
