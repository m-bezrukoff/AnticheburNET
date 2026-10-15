function check(value, message) { if (!value) die(message); }
let settings = {};
let files = {};
let locked = false;
let jobs = [];
let state = null;
let result_ok = true;
let result_changed = true;
let cron_ok = true;
let committed = true;
let write_ok = true;
let current = 0;
let output = null;
let cron = "0 12 * * * other-task\n";
// Explicit router-local Moscow time, independent of the test host timezone.
let timezone_offset = 10800;
localtime = function(now) { return gmtime(now + timezone_offset); };
function at(year, mon, mday, hour, min) {
    current = timegm({ year, mon, mday, hour, min: min || 0 }) - timezone_offset;
}
now_seconds = function() { return current; };
uci_settings = function() { return settings; };
uci_core.set = function(path, value) { settings.release_auto_update_enabled = value; return true; };
uci_core.commit = function(package) { return committed; };
fs.readfile = function(path) { return files[path]; };
write_file = function(path, value) { if (!write_ok) return false; files[path] = value; return true; };
remove_file = function(path) { delete files[path]; };
ensure_dir = function(path) { return true; };
acquire_runtime_lock = function(path, wait) { if (locked) return false; locked = true; return true; };
release_runtime_lock = function(path) { locked = false; };
command_output_from_args = function(args) { check(args[0] == "crontab", "unexpected command"); return cron; };
write_crontab_text = function(value) { if (!cron_ok) return false; cron = value; return true; };
write_json = function(value) { output = value; };
log_message = function(message, level) {};
ensure_component_runtime_dirs = function() { return true; };
component_job_id = function() { return "auto"; };
component_job_state_path_value = function(id) { return "/jobs/auto.json"; };
owner_pid = function() { return "123"; };
write_state_file = function(path, value) {
    if (path == RELEASE_AUTO_UPDATE_RESULT_FILE) {
        if (!write_ok) return false;
        files[path] = sprintf("%J", value);
    }
    else state = value;
    return true;
};
read_json_file = function(path) {
    if (path == RELEASE_AUTO_UPDATE_RESULT_FILE)
        return files[path] == null ? null : json(files[path]);
    return state;
};
let process_identity = "boot-1:1234";
let stat_fields = [ "S" ];
for (let i = 1; i < 19; i++) push(stat_fields, "0");
push(stat_fields, "1234");
files["/proc/sys/kernel/random/boot_id"] = "boot-1\n";
files["/proc/123/stat"] = "123 (worker with spaces) " + join(" ", stat_fields);
check(release_auto_update_process_identity("123") == process_identity, "worker identity parsed a spaced process name incorrectly");
check(release_auto_update_process_identity("../123") == "", "invalid process identity path was accepted");
release_auto_update_process_identity = function(pid) { return process_identity; };
component_action_worker = function(path, out, component, action) {
    check(component == "anticheburnet" && action == "check_and_update", "automatic update included optional providers or bypassed the guarded update");
    check(state.running && state.pid == "123", "automatic update did not publish tracked progress");
    check(release_auto_update_history().status == "running", "active automatic update did not publish a running history status");
    push(jobs, component);
    state = { success: result_ok, running: false, changed: result_changed, current_version: "1.0.16", exit_code: result_ok ? 0 : 1 };
};

at(2026, 10, 15, 12);
check(release_auto_update_settings("") && output.enabled === false, "automatic installation must default to disabled");
check(output.last_run == null, "schedule enable time was fabricated as a previous automatic run");
check(release_update_if_due() && length(jobs) == 0, "disabled schedule installed a release");
check(!release_auto_update_settings("invalid"), "invalid checkbox value was accepted");
check(release_auto_update_settings("1") && output.enabled, "enabling failed");
check(index(cron, "0 4 * * * /usr/bin/anticheburnet release_update_if_due") >= 0, "schedule is not 04:00 router-local time");
check(index(cron, "other-task") >= 0 && index(cron, "*/3") < 0, "schedule changed other cron jobs or used day-of-month stepping");
let anchor = files[RELEASE_AUTO_UPDATE_STATE_FILE];
check(release_auto_update_settings("1") && files[RELEASE_AUTO_UPDATE_STATE_FILE] == anchor, "saving an enabled checkbox reset the interval");
check(length(split(cron, RELEASE_AUTO_UPDATE_CRON_MARKER)) == 2, "schedule was duplicated");
at(2026, 10, 16, 4); check(release_update_if_due() && length(jobs) == 0, "update ran before three calendar days");
at(2026, 10, 18, 3, 59); check(release_update_if_due() && length(jobs) == 0, "update ran before 04:00");
at(2026, 10, 18, 4); check(release_update_if_due() && length(jobs) == 1, "due release did not update");
check(release_auto_update_settings("") && output.last_run.status == "updated" && output.last_run.version == "1.0.16" &&
    output.last_run.local_time == "2026-10-18 04:00:00", "completed update lost its persisted date, router-local time, version or status");
check(release_update_if_due() && length(jobs) == 1, "same due time reinstalled the release");
result_changed = false;
at(2026, 10, 21, 4); check(release_update_if_due() && length(jobs) == 2, "next three-day update did not run");
check(release_auto_update_history().status == "latest", "up-to-date automatic check was reported as a reinstallation");
at(2026, 10, 24, 4); result_ok = false;
let before = files[RELEASE_AUTO_UPDATE_STATE_FILE];
check(!release_update_if_due() && files[RELEASE_AUTO_UPDATE_STATE_FILE] == before && !locked, "failed update advanced the schedule or retained the lock");
check(release_auto_update_history().status == "failed" && release_auto_update_history().local_time == "2026-10-24 04:00:00",
    "failed update did not preserve its completion date and status");
at(2026, 10, 25, 4); result_ok = true;
check(release_update_if_due() && length(jobs) == 4, "failed update did not retry at the next 04:00 window");
locked = true; check(release_update_if_due() && length(jobs) == 4, "concurrent scheduler ran another update"); locked = false;
check(release_auto_update_settings("0") && !output.enabled && index(cron, RELEASE_AUTO_UPDATE_CRON_MARKER) < 0 && index(cron, "other-task") >= 0,
    "disabling did not remove only its own cron entry");
check(output.last_run != null && output.last_run.local_time == "2026-10-25 04:00:00", "disabling discarded automatic update history");
at(2026, 10, 28, 4); check(release_update_if_due() && length(jobs) == 4, "disabled schedule still ran");

for (let dates in [ [2026, 1, 30, 2026, 2, 2], [2028, 2, 27, 2028, 3, 1], [2026, 12, 30, 2027, 1, 2] ]) {
    at(dates[0], dates[1], dates[2], 18);
    check(release_auto_update_settings("1"), "failed to enable at calendar boundary");
    let count = length(jobs);
    at(dates[3], dates[4], dates[5], 4);
    check(release_update_if_due() && length(jobs) == count + 1, "month, leap-year or year boundary broke the three-day interval");
    check(release_auto_update_settings("0"), "failed to disable after boundary test");
}
cron_ok = false; before = files[RELEASE_AUTO_UPDATE_STATE_FILE];
check(!release_auto_update_settings("1") && settings.release_auto_update_enabled == "0" && !locked && files[RELEASE_AUTO_UPDATE_STATE_FILE] == before,
    "failed cron update did not roll back settings and calendar state");
cron_ok = true;
committed = false;
check(!release_auto_update_settings("1") && settings.release_auto_update_enabled == "0" && !locked,
    "failed UCI commit enabled automatic installation or retained the lock");
committed = true;
write_ok = false; check(!release_auto_update_settings("1") && settings.release_auto_update_enabled == "0", "unwritable calendar state enabled automatic installation"); write_ok = true;
check(release_auto_update_settings("1"), "failed to re-enable");
delete files[RELEASE_AUTO_UPDATE_STATE_FILE];
let count = length(jobs);
check(release_update_if_due() && length(jobs) == count && files[RELEASE_AUTO_UPDATE_STATE_FILE] != null,
    "missing persistent state caused an immediate installation");
let plan = cron_refresh_apply_result({ release_auto_update_enabled: "1" }, [], cron, "/usr/bin/anticheburnet", "# list", "# sub", "# component");
check(index(plan.crontab, RELEASE_AUTO_UPDATE_CRON_MARKER) >= 0 && length(split(plan.crontab, RELEASE_AUTO_UPDATE_CRON_MARKER)) == 2, "service cron refresh lost or duplicated the auto-update schedule");
plan = cron_refresh_apply_result({ release_auto_update_enabled: "0" }, [], plan.crontab, "/usr/bin/anticheburnet", "# list", "# sub", "# component");
check(index(plan.crontab, RELEASE_AUTO_UPDATE_CRON_MARKER) < 0 && index(plan.crontab, "other-task") >= 0, "service cron refresh retained a disabled auto-update schedule");
check(release_auto_update_settings("0"), "failed to disable before timezone test");
at(2026, 3, 27, 18);
check(release_auto_update_settings("1"), "failed to enable before timezone change");
timezone_offset = 14400;
at(2026, 3, 30, 4);
count = length(jobs);
check(release_update_if_due() && length(jobs) == count + 1, "daylight saving change delayed the local 04:00 update");
check(release_auto_update_settings("0"), "failed to disable after timezone change");
at(2019, 1, 1, 4);
check(!release_auto_update_settings("1") && settings.release_auto_update_enabled == "0", "unsynchronized router clock enabled automatic installation");
let interrupted_at = timegm({ year: 2026, mon: 10, mday: 15, hour: 1 });
files[RELEASE_AUTO_UPDATE_RESULT_FILE] = sprintf("%J", { started_at: interrupted_at,
    status: "running", pid: "123", process_identity: "old-boot-or-process:0" });
check(release_auto_update_history().status == "interrupted", "rebooted or replaced worker remained in progress forever");
files[RELEASE_AUTO_UPDATE_RESULT_FILE] = "{}";
check(release_auto_update_history() == null, "invalid history fabricated an automatic update");
print("Automatic release update schedule, persistence, failure and calendar checks passed\n");
