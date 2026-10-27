// Appended to subscription/cache.uc; all network and filesystem writes are mocked.
function check(value, message) { if (!value) die(message + "\n"); }
let elapsed = 0, statuses = [], durations = [], calls = [], moved = false;
monotonic_milliseconds = function() { return elapsed; };
unlink_path = function(path) {};
file_nonempty = function(path) { return true; };
move_file = function(source, target) { moved = true; return true; };
command_status_from_args = function(args) {
    let index = length(calls);
    push(calls, args);
    elapsed += durations[index];
    return statuses[index];
};
function run_case(codes, times, budget, expected, attempts) {
    elapsed = 0; statuses = codes; durations = times; calls = []; moved = false;
    let result = download_subscription("https://fixture.test/sub", "/fixture/body", "", "/fixture/headers", "Happ", "fixture", {}, budget);
    check(result == expected && length(calls) == attempts, "Unexpected retry result or attempt count");
    check(moved == (expected == 0), "Only a successful download may replace the response");
    check(elapsed <= budget, "Retries exceeded the shared deadline");
}
run_case([7], [3000], 15000, 7, 1);
check(calls[0][index(calls[0], "--max-time") + 1] == "15.000", "Background request must receive its full time budget");
check(calls[0][index(calls[0], "--connect-timeout") + 1] == 5, "Background connection timeout must allow slow connections");
run_case([6], [100], 15000, 6, 1);
run_case([28], [15000], 15000, 28, 1);
run_case([7], [1000], 2000, 7, 1);
check(calls[0][index(calls[0], "--connect-timeout") + 1] == 1, "Manual updates must retain their fast connection limit");
run_case([22], [100], 15000, 22, 1);

// Verify the scheduled phase survives the actual CLI worker planner.
connections.subscription_urls = function(section) { return ["https://fixture.test/sub"]; };
let plan = "";
system = function(command) { plan = command; return 0; };
update_subscription_sources_parallel({ ".name": "main" }, true, "scheduled");
check(index(plan, "'scheduled'") >= 0, "Scheduled workers must receive the background phase");
update_subscription_sources_parallel({ ".name": "main" }, true);
check(index(plan, "'runtime'") >= 0, "Manual workers must default to the fast runtime phase");

let received_phase;
uci_sections = function() { return [{ ".name": "main" }]; };
subscription_update_section = function(section, force, phase) { received_phase = phase; return 2; };
print_subscription_update_summary = function(summary) {};
subscription_update_request("1", "", "", "scheduled");
check(received_phase == "scheduled", "Cache request must forward its phase to section updates");

let messages = [], errors = [], pauses = [], request_times = [], response_codes = [], completed_requests = 0;
ensure_dir = function(path) { return true; };
read_text = function(path) { return ""; };
get_subscription_user_agent = function(value) { return "Happ"; };
get_subscription_hwid = function(value) { return "fixture"; };
user_agent_candidates = function(configured, cached, fallback) { return ["Happ"]; };
log_message = function(message, level) {
    push(messages, message);
    if (level == "error") push(errors, completed_requests);
};
subscription_parser = function() { return {
    try_decode_gzip_content_file: function(path) { return false; },
    extract_ui_metadata_file: function(headers, raw, output) { return false; }
}; };
reuse_source_response = function() { return true; };
subscription_config_is_current = function() { return true; };
files_equal = function() { return true; };
write_text = function() { return true; };
persist_subscription_cache = function() { return true; };
log_subscription_source_summary = function() {};
download_subscription = function(url, body, proxy, headers, agent, hwid, device, budget) {
    push(request_times, elapsed);
    check(budget == 15000 || budget == 2000, "Every retry must receive a fresh request budget");
    let status = response_codes[completed_requests++];
    elapsed += budget; // Even a full timeout must allow the next delayed attempt.
    return status;
};
command_status_from_args = function(args) {
    check(length(args) == 2 && args[0] == "sleep" && args[1] == "30", "Unexpected retry command");
    push(pauses, elapsed);
    elapsed += 30000;
    check(length(errors) == 0, "No error may be emitted while retries remain");
    return 0;
};
function refresh_case(codes, retry_limit, budget, expected_status, expected_pauses) {
    elapsed = 0; messages = []; errors = []; pauses = []; request_times = []; response_codes = codes; completed_requests = 0;
    let result = download_subscription_into_cache("main", "https://fixture.test/sub", "/fixture/cache.json", "/fixture/cache.url", "", "", "fixture", 1, "main-subscription-1", "", [], {}, budget, retry_limit);
    check(result == expected_status && completed_requests == length(codes), "Unexpected final status or request count");
    check(length(pauses) == expected_pauses, "Unexpected number of 30-second pauses");
    for (let i = 0; i < length(pauses); i++)
        check(request_times[i + 1] - pauses[i] == 30000, "Retry must start 30 seconds after failure");
    if (expected_status == 1)
        check(length(errors) == 1 && errors[0] == length(codes), "Error must appear only after all attempts fail");
    else
        check(length(errors) == 0, "Recovered requests must not emit errors");
    check(index(join("\n", messages), "No compatible") < 0, "Transport failure must not claim profile incompatibility");
}
refresh_case([28, 6, 7, 28], 3, 15000, 1, 3);
check(index(join("\n", messages), "curl exit 28") >= 0, "Final error must include the transport status");
refresh_case([28, 6, 7, 0], 3, 15000, 2, 3);
refresh_case([7, 0], 3, 15000, 2, 1);
refresh_case([0], 3, 15000, 2, 0);
refresh_case([28], 0, 2000, 1, 0);
refresh_case([22], 3, 15000, 1, 0);

// The production source updater must enable delayed retries only for the daily job.
ensure_runtime_dirs = function() {};
uci_named_section = function() { return {}; };
subscription_source_profile = function() { return { valid: true, url: "https://fixture.test/sub" }; };
cached_source_status = function() { return { usable: false, current: false }; };
get_subscription_download_proxy_address = function() { return ""; };
let source_budget, source_retries;
download_subscription_into_cache = function(section, url, body, cached_url, proxy, agent, hwid, source, cache, metadata, sections, device, budget, retries) {
    source_budget = budget; source_retries = retries; return 2;
};
update_subscription_source("main", 1, "fixture", "scheduled", "");
check(source_budget == 15000 && source_retries == 3, "Daily source update must enable three delayed retries");
update_subscription_source("main", 1, "fixture", "runtime", "");
check(source_budget == 2000 && source_retries == 0, "Manual source update must keep its fast limit");
update_subscription_source("main", 1, "fixture", "startup", "");
check(source_budget == 15000 && source_retries == 0, "Startup must not inherit daily retry pauses");
print("Subscription delayed retries, final-only errors, phase propagation and manual limits passed\n");
