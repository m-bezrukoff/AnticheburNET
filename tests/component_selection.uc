function check(value, message) { if (!value) die(message + "\n"); }
let events = [];
let live = { main: "chosen" };
let saved = null;
let ready = true;
let attempts = 0;
file_exists = function(path) { return true; };
anticheburnet_status_running_with_timeout = function() { return true; };
selection.capture = function() { push(events, "capture"); return live; };
selection.save = function(snapshot) { saved = snapshot; return true; };
selection.clear = function() { saved = null; return true; };
selection.restore = function(snapshot) {
    attempts++;
    if (!ready) return false;
    live = snapshot;
    push(events, "restore");
    return true;
};
system = function(command) { return 0; };
updates_log = function(message, level) {};
run_logged = function(message, command) { push(events, "restart"); return true; };
command_success_from_args = function(args) { push(events, args[1]); return true; };

capture_anticheburnet_running_state();
// Model a package hook replacing the running engine before the final restart.
live = { main: "first" };
restart_anticheburnet_after_successful_change();
check(live.main == "chosen" && saved == null, "Component restart lost the pre-install choice");
check(join(",", events) == "capture,restart,restore", "Selection must surround component installation");

anticheburnet_stopped_for_sing_box_change = true;
live = { main: "first" };
restart_anticheburnet_after_failed_sing_box_change();
check(live.main == "chosen", "Rollback must restore the original choice too");

ready = false;
attempts = 0;
restore_component_selection();
check(attempts == 5 && saved.main == "chosen", "Unavailable API must retain a bounded, persistent handoff");
ready = true;
restore_component_selection();
check(saved == null, "Successful restoration must consume the handoff");

anticheburnet_status_running_with_timeout = function() { return false; };
selected_profiles_before_change = null;
events = [];
capture_anticheburnet_running_state();
restart_anticheburnet_after_failed_sing_box_change();
check(length(events) == 0, "Stopped service must not be started or capture a stale selection");
print("Component selection preservation, package hooks, rollback and retry checks passed\n");
