function check(value, message) { if (!value) die(message); }
let state = { kind: "component", component: "anticheburnet", action: "install", running: false,
    success: true, changed: 1, current_version: "1.2.3" };
let calls = [];
let response = '{"kind":"component","component":"anticheburnet","action":"install","running":true,"suite_continuation":true}';
fs.glob = function(pattern) { return [ "/jobs/1.json" ]; };
read_json_file = function(path) { return path == "/jobs/1.json" ? state : null; };
command_output = function(command) { push(calls, command); return response; };
let values = action_state_from_dir("/jobs");
check(length(values) == 1 && values[0].running && values[0].job_id == "1", "UI exposed legacy success before suite completion");
check(length(calls) == 1 && index(calls[0], "UPDATES_JOB_DIR='/jobs'") >= 0,
    "UI did not reconcile the original job in its configured directory");
state.suite_complete = true;
values = action_state_from_dir("/jobs");
check(!values[0].running && length(calls) == 1, "UI started another check for an already complete suite");
state.suite_complete = false;
response = "unavailable";
check(length(action_state_from_dir("/jobs")) == 0, "UI fell back to partial success after a failed handoff read");
response = '{"kind":"component","running":true}';
read_stdin = function() { return "component\t/jobs/1.json\n"; };
check(read_state_paths().component[0].running, "legacy path-based UI reader bypassed suite completion");
print("Suite completion UI status checks passed\n");
