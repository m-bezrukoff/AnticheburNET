function check(value, message) { if (!value) die(message); }
let state = null;
let launched = [];
let locked = false;
let result = null;
let removed = [];
let command = "";
now_seconds = function() { return 100; };
read_json_file = function(path) { return index(path, ".progress") >= 0 ? null : json(sprintf("%J", state)); };
write_state_file = function(path, value) { state = value; return true; };
acquire_runtime_lock = function(path, wait) { if (locked) return false; locked = true; return true; };
release_runtime_lock = function(path) { locked = false; };
launch_component_worker = function(args) { push(launched, args); return "123"; };
set_component_running_job_pid = function(path, pid) { state.pid = pid; return true; };
output_json_object = function(path) { return result; };
update_component_check_cache_from_action = function(value) {};
remove_file = function(path) { push(removed, path); };
function legacy() {
    return { success: true, running: false, kind: "component", component: "anticheburnet",
        action: "install", changed: 1, current_version: "1.2.3", latest_version: "1.2.3", updated_at: 99 };
}
state = legacy();
continue_legacy_suite_job("/jobs/1.json");
check(state.running && state.suite_continuation && state.pid == "123", "legacy success was exposed before completing the suite");
check(length(launched) == 1 && launched[0][0] == "component-action-worker" && launched[0][5] == "1.2.3", "legacy continuation was not pinned to the installed release");
check(launched[0][2] == "/jobs/1.out.suite", "old worker cleanup can delete the continuation output");
continue_legacy_suite_job("/jobs/1.json");
check(length(launched) == 1, "concurrent/repeated polling launched another installer");
result = { success: true, component: "anticheburnet", action: "check_update", changed: 0, suite_complete: true };
finish_component_job("/jobs/1.json", "anticheburnet", "install", 0, "/jobs/1.out");
check(!state.running && state.changed == 1 && state.action == "install" && state.suite_complete,
    "no-op core completion lost the original application upgrade");
continue_legacy_suite_job("/jobs/1.json");
check(length(launched) == 1, "finished suite was continued twice");

for (let key, value in { acked_at: 100, success: false, changed: 0, running: true,
    current_version: "1.2.2", suite_complete: true, suite_continuation: true, updated_at: -4000,
    component: "sing_box", action: "check_update" }) {
    state = legacy(); state[key] = value;
    continue_legacy_suite_job("/jobs/1.json");
    check(length(launched) == 1, "ineligible job was automatically installed: " + key);
}
state = legacy(); locked = true;
continue_legacy_suite_job("/jobs/1.json"); locked = false;
check(length(launched) == 1, "another poll's handoff lock was ignored");
let published = null;
ensure_dir = function(path) { return true; };
component_cleanup_jobs = function() {};
component_job_state_path_value = function(id) { return "/jobs/1.json"; };
refresh_component_running_job_state = function(path) {};
fs.stat = function(path) { return {}; };
write_json = function(value) { published = value; };
state = legacy(); locked = true;
component_action_status("1"); locked = false;
check(published.running && state.running === false, "polling exposed partial success during another reader's handoff claim");

state = legacy();
continue_legacy_suite_job("/jobs/1.json");
result = { success: false, component: "anticheburnet", action: "install", changed: 0, message: "checksum failed" };
finish_component_job("/jobs/1.json", "anticheburnet", "install", 1, "/jobs/1.out");
check(!state.success && !state.running && state.message == "checksum failed", "completion failure was hidden by the old success");
let count = length(launched);
continue_legacy_suite_job("/jobs/1.json");
check(length(launched) == count, "failed completion was retried automatically");
state = { suite_continuation: true };
result = { success: true, component: "anticheburnet", action: "install", changed: 1 };
finish_component_job("/jobs/1.json", "anticheburnet", "install", 0, "/jobs/1.out");
check(!state.success, "application-only success was accepted as a complete release");

launch_component_worker = function(args) { return ""; };
state = legacy(); continue_legacy_suite_job("/jobs/1.json");
check(!state.success && !state.running && state.suite_continuation, "failed worker launch left a successful or running job");
launch_component_worker = function(args) {
    state = { success: true, running: false, suite_complete: true, suite_continuation: true };
    return "123";
};
set_component_running_job_pid = function(path, pid) { return false; };
state = legacy(); continue_legacy_suite_job("/jobs/1.json");
check(state.success && state.suite_complete, "fast completion was overwritten by PID registration failure");
command_status = function(value) { command = value; return 0; };
state = { suite_continuation: true };
result = { success: true, suite_complete: true };
component_action_worker("/jobs/1.json", "/jobs/1.out", "anticheburnet", "install", "1.2.3");
check(index(command, "ANTICHEBURNET_SUITE_TARGET_VERSION='1.2.3'") >= 0, "worker lost the pinned legacy release");
component_action_status_error_exit = function(message) { die(message); };
write_state_file = function(path, value) { return false; };
state = legacy();
let failed = false;
try { continue_legacy_suite_job("/jobs/1.json"); }
catch (e) { failed = true; }
check(failed && !locked, "state write failure exposed success or retained the handoff lock");
print("Legacy one-click suite handoff checks passed\n");
