// Appended to the production helper before its CLI dispatcher.
let test_root = getenv("ANTICHEBURNET_TEST_DIR");
if (!test_root || substr(test_root, 0, 5) != "/tmp/")
    die("ANTICHEBURNET_TEST_DIR must be an isolated /tmp directory");
let test_binary = test_root + "/sing-box";
let test_target = test_root + "/target";
let test_config = test_root + "/config";
let test_calls = [];
let test_stop_ok = true;
let test_packages_ok = true;
function check(value, message) { if (!value) die(message); }
function write_fixture(path) {
    let handle = fs.open(path, "w");
    check(handle != null, "cannot create fixture");
    handle.write("fixture\n");
    handle.close();
}
env = function(name, fallback) {
    return name == "ANTICHEBURNET_INSTALLER_SING_BOX_BIN" ? test_binary : fallback;
};
path_executable = function(path) { return path == "/etc/init.d/sing-box"; };
installer_command_result = function(args, seconds) {
    push(test_calls, join(" ", args));
    return { complete: true, status: test_stop_ok ? 0 : 1 };
};
installer_remove_selected_packages = function() {
    push(test_calls, "remove-packages");
    return test_packages_ok;
};

write_fixture(test_config);
write_fixture(test_binary);
check(installer_prepare_full_suite(), "orphaned binary replacement failed");
check(fs.lstat(test_binary) == null, "orphaned binary survived replacement");
check(join(" ", test_calls) == "/etc/init.d/sing-box stop remove-packages", "incorrect replacement order");
check(read_text_file(test_config) == "fixture\n", "configuration changed");

write_fixture(test_binary);
test_stop_ok = false;
test_calls = [];
check(!installer_prepare_full_suite(), "failed stop accepted");
check(length(test_calls) == 1 && fs.lstat(test_binary) != null, "stop failure removed packages or binary");
test_stop_ok = true;
test_packages_ok = false;
check(!installer_prepare_full_suite(), "failed package removal accepted");
check(fs.lstat(test_binary) != null, "binary removed after package failure");
test_packages_ok = true;
check(fs.unlink(test_binary), "fixture cleanup failed");

write_fixture(test_target);
check(fs.symlink(test_target, test_binary), "cannot create symlink fixture");
check(installer_prepare_full_suite(), "symlink replacement failed");
check(fs.lstat(test_binary) == null, "symlink survived replacement");
check(read_text_file(test_target) == "fixture\n", "symlink target was removed");
check(fs.symlink(test_root + "/absent", test_binary), "cannot create dangling symlink");
check(installer_prepare_full_suite(), "dangling symlink replacement failed");
check(fs.lstat(test_binary) == null, "dangling symlink survived replacement");

check(fs.mkdir(test_binary), "cannot create directory fixture");
check(!installer_prepare_full_suite(), "unlink failure accepted");
check(fs.lstat(test_binary) != null, "binary directory recursively removed");
check(fs.rmdir(test_binary), "directory cleanup failed");
check(installer_prepare_full_suite(), "absent binary replacement failed");
check(read_text_file(test_config) == "fixture\n", "configuration lost");
print("Embedded ucode sing-box replacement checks passed\n");
