// Exercise the real provider owner with isolated files and intercepted external
// boundaries. A GeoIP content update must not invoke any lifecycle operation.
function check(value, message) { if (!value) die(message + "\n"); }
let work = ARGV[0], events = [], scenario = "", confirmations = 0;
let current_path = work + "/current.json", candidate_path = work + "/candidate.json";
let old_path = work + "/" + join("", ["aaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa"]) + ".json";
// Keep the same directory; only the content-addressed basename changes.
let new_path = work + "/" + join("", ["bbbbbbbbbbbbbbbb", "bbbbbbbbbbbbbbbb", "bbbbbbbbbbbbbbbb", "bbbbbbbbbbbbbbbb"]) + ".json";
let rule = { type: "local", tag: "main-out-happ-geoip-cnU=", format: "source", path: old_path };
let old = { configuration: { route: { final: "main-out", rule_set: [rule] }, dns: { strategy: "ipv4_only" } },
    outbounds: [{ type: "direct", tag: "main-out" }] };
let fresh = json(sprintf("%J", old)); fresh.configuration.route.rule_set[0].path = new_path;
let current_config = { route: old.configuration.route, providers: [{ type: "anticheburnet", tag: "anticheburnet-subscriptions", path: current_path + ".providers.json" }] };
let candidate_config = { route: fresh.configuration.route, providers: [{ type: "anticheburnet", tag: "anticheburnet-subscriptions", path: candidate_path + ".providers.json" }] };
uci_settings = function() { return { config_path: current_path }; };
temp_path = function() { return candidate_path; };
sing_box_version = function() { return "1.14.1-extended-2.7.2-anticheburnet.5"; };
service_listen_address_value = function(settings) { return "127.0.0.1"; };
ensure_dir = function(path) { return fs.stat(path) != null || fs.mkdir(path); };
log_message = function(message, level) {};
remove_provider_stage = function(path) {};
command_status = function(command) { check(index(command, "generate-config") >= 0, "Only staged generation is allowed"); return 0; };
command_success_from_args = function(args) { die("No lifecycle or external copy command is allowed\n"); };
command_output_from_args = function(args) { check(args[0] == "sha256sum", "Only provider revision hashing is allowed"); return "revision"; };
save_config_file = function(from, to) {
    push(events, to == current_path ? "config" : "provider");
    if (scenario == "config-failure" && to == current_path) return false;
    return fs.rename(from, to);
};
runtime_awg.plan_update = function(old_profiles, new_profiles, outbounds) { return {}; };
runtime_awg.begin_update = function(path, plan) { push(events, "prepare"); return true; };
runtime_awg.commit_update = function(path, plan) { push(events, "commit"); return true; };
runtime_awg.rollback_update = function(path, plan) { push(events, "rollback"); return true; };
selection.capture = function() { return { "main-out": "chosen-profile" }; };
selection.restore = function(snapshot) { check(snapshot["main-out"] == "chosen-profile", "Selection must survive"); push(events, "selection"); return true; };
module_success = function(args) {
    if (index(args[0], "validator.uc") >= 0) return false;
    check(args[1] == "clash-api", "Only the provider API may be called");
    if (args[2] == "provider_supports_rulesets") { push(events, "capability"); return scenario != "old-core"; }
    check(args[2] == "update_provider", "No service restart or other API operation is allowed");
    confirmations++; push(events, "confirm" + confirmations);
    let config = read_json_file(current_path), payload = read_json_file(current_path + ".providers.json");
    check(config.providers[0].path == current_path + ".providers.json", "Saved config must reference the permanent provider file");
    check(config.route.rule_set[0].path == payload.configuration.route.rule_set[0].path,
        "Disk configuration and provider must use the same GeoIP generation");
    return scenario == "success" || confirmations > 1;
};
for (let name in ["success", "rejected", "config-failure", "old-core", "routing-change", "dns-change", "different-source", "different-format", "different-tag", "unmanaged-set"]) {
    scenario = name; events = []; confirmations = 0;
    let incoming = json(sprintf("%J", fresh));
    if (name == "routing-change") incoming.configuration.route.final = "changed";
    if (name == "dns-change") incoming.configuration.dns.strategy = "prefer_ipv6";
    if (name == "different-source") incoming.configuration.route.rule_set[0].path = "/another/" + split(new_path, "/")[-1];
    if (name == "different-format") incoming.configuration.route.rule_set[0].format = "binary";
    if (name == "different-tag") incoming.configuration.route.rule_set[0].tag = "other-happ-geoip-cnU=";
    if (name == "unmanaged-set") incoming.configuration.route.rule_set[0].tag = "custom-rules";
    fs.writefile(current_path, sprintf("%J", current_config));
    fs.writefile(candidate_path, sprintf("%J", candidate_config));
    fs.writefile(current_path + ".providers.json", sprintf("%J", old));
    fs.writefile(candidate_path + ".providers.json", sprintf("%J", incoming));
    fs.writefile(current_path + ".awg.json", "[]");
    fs.writefile(candidate_path + ".awg.json", "[]");
    check(update_providers(false) == (name == "success"), "Only compatible confirmed GeoIP updates may succeed: " + name);
    let expected = name == "success" ? ["capability", "prepare", "provider", "config", "confirm1", "selection", "commit"] :
        name == "rejected" ? ["capability", "prepare", "provider", "config", "confirm1", "confirm2", "selection", "rollback"] :
        name == "config-failure" ? ["capability", "prepare", "provider", "config", "rollback"] : name == "old-core" ? ["capability"] : [];
    check(sprintf("%J", events) == sprintf("%J", expected), "Unexpected transaction order: " + name);
    let saved = read_json_file(current_path), payload = read_json_file(current_path + ".providers.json");
    let expected_path = name == "success" ? new_path : old_path;
    check(saved.route.rule_set[0].path == expected_path && payload.configuration.route.rule_set[0].path == expected_path,
        "Rejected/failed updates must restore both disk files: " + name);
    check((fs.stat(current_path + ".providers.pending") != null) == (name != "success"), "Failures must remain pending");
}
print("Automatic GeoIP provider transactions and rollback checks passed\n");
