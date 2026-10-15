// Appended to the runtime owner by awg_provider_refresh.sh. Intercept external
// boundaries while exercising the actual provider transaction and AWG planner.
function check(value, message) { if (!value) die(message + "\n"); }
let work = ARGV[0], events = [], scenario = "", confirmations = 0;
let current_path = work + "/current.json", candidate_path = work + "/candidate.json";
let key = b64enc("01234567890123456789012345678901");
let native = "[Interface]\nPrivateKey = " + key + "\nAddress = 10.7.0.2/32\nJc = 6\n" +
    "[Peer]\nPublicKey = " + key + "\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:443\n";
let current_config = { providers: [{ type: "anticheburnet", tag: "anticheburnet-subscriptions", path: current_path + ".providers.json" }] };
let candidate_config = { providers: [{ type: "anticheburnet", tag: "anticheburnet-subscriptions", path: candidate_path + ".providers.json" }] };
let old = { configuration: { route: { final: "main-out" } }, outbounds: [{ type: "direct", tag: "old", bind_interface: "acawg1" }] };
let fresh = { configuration: old.configuration, outbounds: [
    { type: "direct", tag: "new", bind_interface: "acawg1" }, { type: "direct", tag: "old", bind_interface: "acawg2" }] };
let old_manifest = [{ interface: "acawg1", table: 312, config: native }];
let fresh_manifest = [{ interface: "acawg1", table: 312, config: replace(native, "vpn.example", "new.example") },
    { interface: "acawg2", table: 313, config: native }];
uci_settings = function() { return { config_path: current_path }; };
temp_path = function() { return candidate_path; };
sing_box_version = function() { return "1.14.1-extended-2.7.2-anticheburnet.3"; };
service_listen_address_value = function(settings) { return "127.0.0.1"; };
ensure_dir = function(path) { return fs.stat(path) != null || fs.mkdir(path); };
log_message = function(message, level) {};
remove_provider_stage = function(path) {};
command_status = function(command) { check(index(command, "generate-config") >= 0, "Only staged generation is allowed"); return 0; };
command_success_from_args = function(args) { die("No lifecycle or external copy command is allowed\n"); };
command_output_from_args = function(args) {
    check(args[0] == "sha256sum", "Only provider revision hashing is allowed");
    return index(fs.readfile(args[1]), '"new"') >= 0 ? "new-revision" : "old-revision";
};
save_config_file = function(from, to) {
    push(events, "publish");
    if (scenario == "file-failure") return false;
    return fs.rename(from, to);
};
runtime_awg.begin_update = function(path, plan) {
    push(events, "prepare");
    check(plan.next[0].config == native && length(plan.added) == 1, "Old AWG slot must survive insertion");
    return scenario != "readiness-failure";
};
runtime_awg.commit_update = function(path, plan) { push(events, "commit"); return scenario != "cleanup-failure"; };
runtime_awg.rollback_update = function(path, plan) { push(events, "rollback"); return true; };
module_success = function(args) {
    if (index(args[0], "validator.uc") >= 0) return false;
    check(args[1] == "clash-api" && args[2] == "update_provider", "Only dynamic provider API calls are allowed");
    confirmations++;
    push(events, "confirm" + confirmations);
    if (confirmations == 1) {
        let applied = read_json_file(current_path + ".providers.json");
        check(applied.outbounds[0].bind_interface == "acawg2" && applied.outbounds[1].bind_interface == "acawg1",
            "Published provider must reference ready, stable AWG interfaces");
    }
    if (scenario == "uncertain") return false;
    return scenario != "rejected" || confirmations > 1;
};
for (let name in [ "success", "cleanup-failure", "readiness-failure", "file-failure", "rejected", "uncertain", "routing-change" ]) {
    scenario = name; events = []; confirmations = 0;
    fs.writefile(current_path, sprintf("%J", current_config));
    fs.writefile(candidate_path, sprintf("%J", candidate_config));
    fs.writefile(current_path + ".providers.json", sprintf("%J", old));
    fs.writefile(candidate_path + ".providers.json", sprintf("%J", fresh));
    fs.writefile(current_path + ".awg.json", sprintf("%J", old_manifest));
    fs.writefile(candidate_path + ".awg.json", sprintf("%J", fresh_manifest));
    if (name == "routing-change") {
        let changed = json(sprintf("%J", fresh)); changed.configuration.route.final = "changed";
        fs.writefile(candidate_path + ".providers.json", sprintf("%J", changed));
    }
    check(update_providers(false) == (name == "success"), "Provider outcome must match native/API confirmation");
    let expected = (name == "success" || name == "cleanup-failure") ? ["prepare", "publish", "confirm1", "commit"] :
        name == "readiness-failure" ? ["prepare"] : name == "file-failure" ? ["prepare", "publish", "rollback"] :
        name == "routing-change" ? [] : name == "rejected" ? ["prepare", "publish", "confirm1", "confirm2", "rollback"] :
        ["prepare", "publish", "confirm1", "confirm2"];
    check(sprintf("%J", events) == sprintf("%J", expected), "AWG cleanup must follow definitive provider confirmation");
    check((fs.stat(current_path + ".providers.pending") != null) == (name != "success"), "Unconfirmed updates must remain pending");
    if (name != "success" && name != "cleanup-failure")
        check(sprintf("%J", read_json_file(current_path + ".providers.json")) == sprintf("%J", old),
            "Failed publication must preserve or restore the previous provider file");
}
print("Provider AWG transaction ordering, failure, rollback, uncertain outcome and routing guard checks passed\n");
