function check(value, message) { if (!value) die(message); }
let events = [];
let plan_args = [];
let root_url = "https://github.com/m-bezrukoff/AnticheburNET/releases/download/1.2.3/";
let core_names = [
    "sing-box-extended_1.14.1-extended-2.7.2-anticheburnet.3_openwrt_aarch64_cortex-a53.apk",
    "anticheburnet-amneziawg_3.1.20260828-r4_aarch64_cortex-a53.apk"
];
let plan_fields = [ "release", "anticheburnet_1.2.3.apk", root_url + "anticheburnet_1.2.3.apk",
    "luci-app-anticheburnet_1.2.3.apk", root_url + "luci-app-anticheburnet_1.2.3.apk", "", "" ];
for (let name in core_names) push(plan_fields, name, root_url + name);
let installed_versions = { "sing-box-extended": "1.14.1-r3", "anticheburnet-xray": null,
    "anticheburnet-amneziawg": "3.1.20260828-r4", anticheburnet: "1.2.3", "luci-app-anticheburnet": "1.2.3" };
is_apk = function() { return true; };
read_openwrt_release_value = function(key) { return key == "DISTRIB_ARCH" ? "aarch64_cortex-a53" : "mediatek/filogic"; };
pkg_is_installed = function(name) { return installed_versions[name] != null; };
installed_package_version = function(name) { return installed_versions[name] || ""; };
sing_box_runtime_output = function(mode, args) { return "1.14.1-extended-2.7.2-anticheburnet.3"; };
compare_versions = function(a, b) { return a == b ? 0 : (a == "newer" ? 1 : -1); };
latest_anticheburnet_release_json = function() { return "release json"; };
helper_output_input = function(input, mode, args) { plan_args = args; return join("\t", plan_fields) + "\n"; };
let suite = resolve_anticheburnet_release("1.2.3");
check(suite != null && length(suite.packages) == 4 && suite.cores_required, "English suite did not resolve");
check(plan_args[3] == "aarch64_cortex-a53" && plan_args[4] == "1", "architecture or complete-suite requirement lost");
check(!anticheburnet_cores_need_update(suite), "sing-box binary and APK version mismatch caused unnecessary update");
check(!anticheburnet_suite_needs_update(suite, "1.2.3"), "current complete suite was considered outdated");
installed_versions["luci-app-anticheburnet"] = "old";
check(anticheburnet_suite_needs_update(suite, "1.2.3"), "outdated LuCI was not detected");
installed_versions["luci-app-anticheburnet"] = "1.2.3";
installed_versions["anticheburnet-xray"] = "old";
check(anticheburnet_suite_needs_update(suite, "1.2.3"), "installed Xray did not trigger migration");
installed_versions["anticheburnet-xray"] = null;
installed_versions["anticheburnet-amneziawg"] = null;
check(anticheburnet_suite_needs_update(suite, "1.2.3"), "missing core was not detected");
installed_versions["anticheburnet-amneziawg"] = "newer";
check(!anticheburnet_suite_needs_update(suite, "1.2.3"), "newer installed core would be downgraded");
installed_versions["anticheburnet-amneziawg"] = "3.1.20260828-r4";
let saved_url = plan_fields[8];
plan_fields[8] = "https://example/foreign.apk";
check(resolve_anticheburnet_release("1.2.3") == null, "foreign release core URL accepted");
plan_fields[8] = saved_url;
let original_getenv = getenv;
let original_latest_release = latest_anticheburnet_release_json;
let tag_url = "";
getenv = function(name) { return name == "ANTICHEBURNET_SUITE_TARGET_VERSION" ? "1.2.3" : original_getenv(name); };
latest_anticheburnet_release_json = function() { die("legacy completion followed a newer latest release"); };
http_get = function(url) { tag_url = url; return "pinned release"; };
helper_success_input = function(input, mode, args) { return true; };
check(resolve_anticheburnet_release("1.2.3") != null && index(tag_url, "/releases/tags/1.2.3") > 0,
    "legacy completion did not resolve the original release tag");
getenv = original_getenv;
latest_anticheburnet_release_json = original_latest_release;

// Optional providers must not participate even when installed and outdated.
provider_installed = function(runtime) { die("release update queried an optional provider"); };
resolve_zapret_release = function(arch) { die("release update queried Zapret"); };
resolve_zapret2_release = function(arch) { die("release update queried Zapret2"); };
resolve_byedpi_release = function(arch) { die("release update queried ByeDPI"); };
action_fail = function(component, action, message) { die(message); };

let originals = {};
for (let name in [ "anticheburnet", "anticheburnet_xray", "anticheburnet_awg", "sing-box" ])
    originals["/etc/config/" + name] = "user settings: " + name;
let files = {};
let download_failure = "";
let checksum_failure = "";
let stop_ok = true;
let install_ok = true;
let backup_ok = true;
let complete_install = true;
let success = false;
let installed_command = "";
report_update_progress = function(stage, detail) { push(events, "progress:" + stage); };
updates_log = function(message, level) {};
write_anticheburnet_latest_version_cache = function(version, now) {};
init_tmp_dir = function() { tmp_dir = "/test"; return true; };
now_seconds = function() { return 1; };
owner_pid = function() { return "test"; };
download_with_retry = function(url, file, name) { push(events, "download:" + name); files[file] = "package"; return name != download_failure; };
download_zapret_bundle_package = function(release, component, action) { die("release update downloaded Zapret"); };
verify_release_package = function(file, name, manifest) { push(events, "verify:" + name); return name != checksum_failure; };
file_exists = function(path) { return files[path] != null || path == SERVICE_INIT; };
read_file = function(path) { return files[path] || ""; };
ensure_dir = function(path) { push(events, "backup"); return backup_ok; };
command_success_from_args = function(args) {
    if (args[0] == "cp") { files[args[3]] = files[args[2]]; push(events, "copy:" + args[2]); }
    return true;
};
command_success = function(command) { return true; };
remove_file = function(path) {};
run_logged = function(label, command) {
    if (index(label, "Stopping AnticheburNET") == 0) { push(events, "stop"); return stop_ok; }
    push(events, "install");
    installed_command = command;
    for (let path, content in originals) files[path] = "package defaults";
    if (install_ok && complete_install) {
        installed_versions.anticheburnet = "1.2.3";
        installed_versions["luci-app-anticheburnet"] = "1.2.3";
        installed_versions["anticheburnet-amneziawg"] = "3.1.20260828-r4";
    }
    return install_ok;
};
disable_standalone_service = function(component) { die("release update changed an optional service"); };
restart_anticheburnet_after_successful_change = function() { push(events, "restart"); };
clear_version_caches = function() {};
wait_anticheburnet_running_after_sing_box_change = function() { return true; };
action_success = function(component, action, message) { success = true; };
function reset() {
    events = []; files = {}; success = false; installed_command = "";
    anticheburnet_was_running = true; anticheburnet_stopped_for_sing_box_change = false;
    suite_complete = false;
    installed_versions["anticheburnet-amneziawg"] = "old";
    for (let path, content in originals) files[path] = content;
    for (let name in [ "zapret", "zapret2", "byedpi" ]) {
        installed_versions[name] = "old";
        files["/etc/config/" + name] = "optional user settings";
    }
}
function expect_failure(label) {
    let failed = false;
    try { install_anticheburnet("1.2.3", suite); }
    catch (e) { failed = true; }
    check(failed && !success, label + " was reported as success");
}
reset();
installed_versions.anticheburnet = "old";
installed_versions["luci-app-anticheburnet"] = "old";
install_anticheburnet("1.2.3", suite);
check(success, "complete-suite installation did not finish");
check(index(events, "install") > index(events, "stop") && index(events, "stop") > index(events, "verify:" + core_names[1]), "engines changed before integrity verification");
for (let asset in suite.packages) check(index(installed_command, asset.file) >= 0, "release package missing from transaction");
for (let name in [ "zapret", "zapret2", "byedpi" ]) {
    check(index(installed_command, name) < 0, "optional provider included in release transaction");
    check(files["/etc/config/" + name] == "optional user settings", "optional provider settings changed");
}
check(index(installed_command, "'apk' '--preserve-env' 'add'") >= 0 && index(installed_command, "ANTICHEBURNET_DEFER_PACKAGE_RESTART='1'") >= 0, "APK hooks did not receive restart deferral");
for (let path, content in originals) check(files[path] == content, "user config was replaced: " + path);
check(index(events, "restart") > index(events, "copy:/root/anticheburnet-backups/update-1-test/sing-box.uci"), "service restarted before config restore");
check(suite_complete, "successful installation did not mark the complete release");
events = []; success = false;
install_anticheburnet("1.2.3", suite);
check(success && length(events) == 1 && events[0] == "progress:resolving", "second press downloaded, installed or restarted the current suite");
reset(); download_failure = core_names[1]; expect_failure("download failure");
check(index(events, "stop") < 0 && index(events, "install") < 0, "download failure changed services");
download_failure = "";
reset(); checksum_failure = core_names[1]; expect_failure("core checksum failure");
check(index(events, "stop") < 0 && index(events, "install") < 0, "checksum failure changed services");
checksum_failure = "";
reset(); backup_ok = false; expect_failure("backup failure");
check(index(events, "stop") < 0 && index(events, "install") < 0, "backup failure changed services");
backup_ok = true;
reset(); stop_ok = false; expect_failure("stop failure");
check(index(events, "install") < 0, "failed stop allowed installation");
stop_ok = true;
reset(); install_ok = false; expect_failure("package failure");
for (let path, content in originals) check(files[path] == content, "failed installation lost user config");
install_ok = true;
reset(); complete_install = false; expect_failure("incomplete package transaction");
check(!suite_complete, "incomplete core installation was reported as a complete release");
complete_install = true;
installed_versions["anticheburnet-amneziawg"] = "3.1.20260828-r4";

let called = "";
let comparison = "0";
latest_anticheburnet_version = function() { return "1.2.3"; };
helper_success = function(mode, args) { return true; };
helper_output = function(mode, args) { return comparison; };
resolve_anticheburnet_release = function(version) { return suite; };
install_anticheburnet = function(version, release) { called = "install"; };
check_anticheburnet = function() { called = "check"; };
check_and_update_anticheburnet();
check(called == "check", "unchanged complete suite was reinstalled");
installed_versions["anticheburnet-xray"] = "old";
check_and_update_anticheburnet();
check(called == "install", "current app did not update its outdated core");
installed_versions["anticheburnet-xray"] = null;
called = ""; check_and_update_anticheburnet();
check(called == "check", "outdated optional providers triggered release installation");
comparison = "1"; called = ""; check_and_update_anticheburnet();
check(called == "check", "development app was downgraded");
// Even a stale Update button uses the guarded complete-suite decision.
acquire_component_lock = function() { return true; };
capture_anticheburnet_running_state = function() {};
comparison = "0"; called = "";
component_action("anticheburnet", "install");
check(called == "check", "direct install bypassed the current-suite guard");
installed_versions["anticheburnet-amneziawg"] = "old"; called = "";
component_action("anticheburnet", "install");
check(called == "install", "direct update did not complete its outdated core");
print("Complete-suite update, configuration and failure checks passed\n");
