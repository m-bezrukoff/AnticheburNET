function check(value, message) { if (!value) die(message + "\n"); }
let events, saved, live, scenario, restores;
fs.stat = function(path) { return {}; };
log_message = function(message, level) {};
release_reload_lock = function() { push(events, "unlock"); };
remove_file = function(path) { push(events, "remove"); };
sing_box_runtime_pid = function() { return "123"; };
capture_selector_state = function() { push(events, "capture"); return scenario == "offline" ? null : live; };
selection.save = function(snapshot) {
    push(events, "save");
    if (scenario == "save-failure") return false;
    saved = snapshot; return true;
};
selection.read = function() { return saved; };
selection.clear = function() { saved = null; push(events, "clear"); return true; };
selection.restore = function(snapshot) {
    restores++;
    check(snapshot.main == "chosen", "DNS reload must restore the original choice");
    if (scenario == "restore-failure" || (scenario == "delayed" && restores < 3)) return false;
    live = snapshot; push(events, "restore"); return true;
};
module_capture = function(path, args) {
    check(args[0] == "patch-dns-config", "Unexpected capture boundary");
    return { status: 0, output: scenario == "unchanged" ? "0" : "1\tbackup" };
};
module_success = function(path, args) {
    push(events, args[0]);
    return scenario != "commit-failure" || args[0] != "commit-state";
};
module_status = function(path, args) {
    push(events, args[0]);
    check(saved != null && saved.main == "chosen", "Choice must be saved before any DNS runtime reload");
    live = { main: "first" };
    return 0;
};
command_success_from_args = function(args) { check(args[0] == "sleep", "No external commands allowed"); return true; };
wait_dns_failover_state = function(path, attempts) {
    return scenario == "rollback" || (scenario == "fallback" && attempts == 5) ? 1 : 0;
};
for (let name in ["success", "fallback", "rollback", "commit-failure", "delayed", "restore-failure", "offline", "save-failure", "unchanged"]) {
    scenario = name; events = []; saved = null; live = { main: "chosen" }; restores = 0;
    let result = dns_failover_apply("candidate");
    let failed = index(["rollback", "commit-failure", "restore-failure", "offline", "save-failure"], name) >= 0;
    check(result == (failed ? 1 : 0), "Unexpected DNS apply result: " + name);
    check(events[-1] == "unlock", "DNS apply must release its lock: " + name);
    if (name == "offline" || name == "save-failure" || name == "unchanged") {
        check(index(events, "hup-sing-box-runtime") < 0 && restores == 0, "Unsafe or unnecessary reload: " + name);
        check(live.main == "chosen", "Cancelled reload changed selection");
    }
    else if (name == "restore-failure")
        check(restores == 5 && saved.main == "chosen", "Failed restoration must keep a bounded persistent handoff");
    else {
        check(live.main == "chosen" && saved == null, "DNS reload/rollback lost the selection: " + name);
        if (name == "delayed") check(restores == 3, "Provider readiness must be retried");
        if (name == "fallback" || name == "rollback")
            check(index(events, "reload-sing-box-runtime") >= 0, "Fallback reload was not exercised");
        if (name == "rollback" || name == "commit-failure")
            check(index(events, "restore-dns-config") < index(events, "restore"), "Selection must be restored after rollback");
    }
}
print("DNS selection preservation: HUP, fallback, rollback, commit failure, readiness retries, offline API, save failure and unchanged config passed\n");
