// Appended to components/updates.uc; only the external configuration/cron
// boundaries are replaced, while exercising the real setting and daily job.
function check(value, message) { if (!value) die(message + "\n"); }
let sections = [{ ".name": "main", enabled: "1", action: "connection",
    subscription_urls: ["https://example.test/sub"], subscription_update_interval: "bad" }];
let plan = cron_refresh_plan_rows({}, sections, "/bin/app", "# lists", "# subs", "# components");
check(plan.status == 0 && join(",", plan.rows) == "subscription\t0 3 * * * /bin/app subscription_update_daily # subs",
    "Daily schedule must default on, independent of legacy intervals");
plan = cron_refresh_plan_rows({ subscription_auto_update_enabled: "0" }, sections, "/bin/app", "# lists", "# subs", "# components");
check(plan.status == 0 && length(plan.rows) == 0, "Disabled checkbox must remove subscription jobs");
let stored = null, locked = false, fail_cron = false, written = "", response;
uci_settings = function() { return stored == null ? {} : { subscription_auto_update_enabled: stored }; };
uci_core.get = function(path) { return stored; };
uci_core.set = function(path, value) { stored = value; return true; };
uci_core.delete = function(path) { stored = null; return true; };
uci_core.commit = function(name) { return true; };
acquire_runtime_lock = function(path, wait) { return !locked; };
release_runtime_lock = function(path) {};
write_json = function(value) { response = value; };
command_output_from_args = function(args) {
    check(args[0] == "crontab", "Only the crontab may be read");
    return "0 1 * * * /bin/keep # unrelated\n* * * * * " + BIN_PATH + " subscription_update_if_due " + SUBSCRIPTION_UPDATE_CRON_MARKER + "\n";
};
write_crontab_text = function(value) { if (fail_cron) return false; written = value; return true; };
check(subscription_auto_update_settings("") && response.enabled, "Existing installations must default to daily refresh");
check(!subscription_auto_update_settings("bad") && stored == null, "Invalid input must not change configuration");
check(subscription_auto_update_settings("0") && stored == "0" && !response.enabled, "Checkbox off must persist immediately");
check(written == "0 1 * * * /bin/keep # unrelated\n", "Disabling must remove legacy subscription jobs and preserve unrelated jobs");
check(subscription_auto_update_settings("1") && stored == "1" && response.enabled, "Checkbox on must persist immediately");
check(index(written, "0 3 * * * " + BIN_PATH + " subscription_update_daily") >= 0, "Enabling must install the 03:00 job");
fail_cron = true;
check(!subscription_auto_update_settings("0") && stored == "1", "Cron write failure must roll back the saved setting");
fail_cron = false; locked = true;
check(!subscription_auto_update_settings("0") && stored == "1", "Concurrent refresh must reject setting changes without losing configuration");
locked = false;
let refreshed = 0, exit_status = -1;
log_message = function(message, level) {};
subscription_update_common = function(force, section, source, phase) {
    check(phase == "scheduled", "Daily job must select the background request budget");
    check(force && section == "" && source == "", "Daily job must refresh all active sources regardless of recent manual updates");
    refreshed++; return 0;
};
exit = function(status) { exit_status = status; };
subscription_update_daily();
check(refreshed == 1 && exit_status == 0, "Enabled daily job must update subscriptions");
stored = "0";
subscription_update_daily();
check(refreshed == 1, "A stale cron invocation must respect the disabled checkbox");

// Verify the scheduled phase reaches the cache subprocess, beyond the daily entry point.
let captured_args;
subscription_cache_capture = function(args) { captured_args = args; return {}; };
apply_subscription_update_result = function(result) { return true; };
check(subscription_update_common_locked(true, "", "", "scheduled"), "Scheduled cache invocation must complete");
check(captured_args[4] == "scheduled", "Daily phase must reach the cache CLI");
subscription_update_common_locked(true, "main", "1");
check(captured_args[4] == "runtime", "Manual cache invocation must retain the fast phase");
print("Daily schedule, setting persistence, cron migration, rollback, concurrency and all-source refresh passed\n");
