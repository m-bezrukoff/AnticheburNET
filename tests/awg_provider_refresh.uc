let fs = require("fs");
function check(value, message) { if (!value) die(message + "\n"); }
let fake = ARGV[1] + ".refresh";
fs.mkdir(fake);
fs.mkdir(fake + "/state");
fs.mkdir(fake + "/sockets");
fs.mkdir(fake + "/bin");
let source = fs.readfile(fs.dirname(sourcepath()) + "/../anticheburnet/files/usr/lib/singbox/awg.uc");
source = replace(source, "/etc/init.d/anticheburnet-awg-subscriptions", fake + "/service");
source = replace(source, /\/var\/run\/anticheburnet/g, fake + "/state");
source = replace(source, /\/var\/run\/amneziawg/g, fake + "/sockets");
source = replace(source, /\/usr\/bin/g, fake + "/bin");
fs.writefile(fake + "/refresh_awg.uc", source);
push(REQUIRE_SEARCH_PATH, fake + "/*.uc");
let owner = require("refresh_awg");
fs.writefile(fake + "/service", "");
fs.writefile(fake + "/bin/amneziawg-go", "");
fs.writefile(fake + "/bin/awg", "");
let key = b64enc("01234567890123456789012345678901");
let config = "[Interface]\nPrivateKey = " + key + "\nAddress = 10.7.0.2/32\nJc = 6\n" +
    "[Peer]\nPublicKey = " + key + "\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:443\n";
let old = [{ interface: "acawg1", table: 312, config }];
let incoming = [{ interface: "acawg1", table: 312, config: replace(config, "vpn.example", "new.example") },
    { interface: "acawg2", table: 313, config }];
let payload = [{ type: "direct", tag: "new", bind_interface: "acawg1" },
    { type: "direct", tag: "old", bind_interface: "acawg2" }];
let plan = owner.plan_update(old, incoming, payload);
check(payload[0].bind_interface == "acawg2" && payload[1].bind_interface == "acawg1",
    "Inserting or reordering AWG must preserve the existing interface binding");
check(length(plan.added) == 1 && plan.added[0].table == 313, "Only new profiles reserve another routing table");
let manifest = fake + "/active.json";
fs.writefile(manifest, sprintf("%J", old));
fs.writefile(fake + "/state/awg-acawg1.ready", "old-ready");
fs.writefile(fake + "/sockets/acawg1.sock", "old-socket");
let registered = { acawg1: { pid: 100 } }, commands = [], make_ready = true, reject_add = false;
let original_popen = fs.popen;
fs.popen = function(command, mode) {
    check(index(command, "call service list") >= 0, "Only the native instance registry may be read");
    return { read: function(_mode) { return sprintf("%J", { "anticheburnet-awg-subscriptions": { instances: registered } }); },
        close: function() { return 0; } };
};
system = function(command) {
    let parsed = match(command, / call service (add|delete) '(.*)' >/);
    check(parsed != null, "No service restart or unrelated command is allowed");
    let data = json(parsed[2]);
    push(commands, { method: parsed[1], data });
    if (parsed[1] == "add") {
        if (reject_add) return 1;
        for (let name, instance in data.instances) {
            check(registered[name] == null, "An existing native instance must never be replaced");
            let active = owner.profiles(instance.command[2]);
            check(active[int(instance.command[4]) - 1].interface == name, "Runner index must resolve its own profile");
            registered[name] = { pid: 200 + length(commands) };
            if (make_ready) {
                fs.writefile(fake + "/state/awg-" + name + ".ready", "new-ready");
                fs.writefile(fake + "/sockets/" + name + ".sock", "new-socket");
            }
        }
    }
    else {
        check(data.instance != "acawg1" || payload[1] == null, "Old AWG must remain until provider confirmation");
        delete registered[data.instance];
        fs.unlink(fake + "/state/awg-" + data.instance + ".ready");
        fs.unlink(fake + "/sockets/" + data.instance + ".sock");
    }
    return 0;
};
sleep = function(ms) {};
check(owner.begin_update(manifest, plan), "New AWG must become ready before provider publication");
check(length(commands) == 1 && registered.acawg1.pid == 100, "Adding AWG must preserve the old process");
check(owner.commit_update(manifest, plan), "Confirmed provider must commit its AWG manifest");
check(fs.readfile(fake + "/state/awg-acawg1.ready") == "old-ready", "Old readiness must survive addition");
check((fs.stat(manifest).mode & 0777) == 0600, "Manifests with private keys must remain private");

let current = owner.profiles(manifest);
let rotating = [{ interface: "acawg1", table: 312, config: replace(config, "vpn.example", "rotated.example") }];
plan = owner.plan_update(current, rotating, []);
check(owner.begin_update(manifest, plan), "Profile rotation must start alongside both old profiles");
check(owner.rollback_update(manifest, plan), "Rejected provider must remove only the newly started profile");
check(registered.acawg1.pid == 100 && registered.acawg2 != null && registered.acawg3 == null,
    "Provider rollback must preserve all previous AWG instances");

make_ready = false;
plan = owner.plan_update(current, rotating, []);
check(!owner.begin_update(manifest, plan), "Readiness timeout must reject publication");
check(registered.acawg1.pid == 100 && registered.acawg3 == null, "Readiness failure must clean only the new instance");
reject_add = true;
check(!owner.begin_update(manifest, plan), "Failed instance registration must reject publication");
check(sprintf("%J", owner.profiles(manifest)) == sprintf("%J", current), "Start failure must restore the old manifest");
reject_add = false;
make_ready = true;

// Remove the first slot, then refresh again with the surviving profile first in
// the downloaded subscription. Sparse manifests must retain its runner index.
payload = [];
plan = owner.plan_update(current, [incoming[0]], []);
check(owner.begin_update(manifest, plan) && registered.acawg1 != null, "Removal must wait for provider confirmation");
check(owner.commit_update(manifest, plan), "Confirmed removal must clean only obsolete interfaces");
current = owner.profiles(manifest);
check(current[0] == null && current[1].interface == "acawg2", "Removing a profile must leave stable slots");
plan = owner.plan_update(current, [incoming[0]], []);
let count = length(commands);
check(owner.begin_update(manifest, plan) && owner.commit_update(manifest, plan) && length(commands) == count,
    "Repeated unchanged refresh must not restart native interfaces");
// A previous cleanup may already have removed the process before interruption.
plan = owner.plan_update(current, [], []);
delete registered.acawg2;
fs.unlink(fake + "/state/awg-acawg2.ready");
fs.unlink(fake + "/sockets/acawg2.sock");
check(owner.commit_update(manifest, plan), "Cleanup retries must be idempotent");
check(length(owner.profiles(manifest)) == 0, "Removing the final AWG must publish an empty manifest");

let full = [];
for (let i = 0; i < 32; i++) push(full, { interface: "acawg" + (i + 1), table: 312 + i, config: config + "# " + i });
let rejected = false;
try { owner.plan_update(full, rotating, []); } catch (error) { rejected = true; }
check(rejected, "Slot exhaustion must preserve old tunnels instead of replacing one before confirmation");
fs.popen = original_popen;
print("AWG automatic addition, stable slots, readiness, rotation, rollback, removal and private manifest checks passed\n");
