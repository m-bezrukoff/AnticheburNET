// Appended to the production installer helper, before its CLI dispatcher.
let test_packages = [];
let test_calls = [];
let test_plan = [];
let test_environment = {};
let test_reverse = "";
let test_reverse_package = "sing-box-extended";
let test_stop_status = 0;
let test_dns_ok = true;
let test_remove_ok = true;

function check(value, message) { if (!value) die(message); }
installer_installed_package_names = function() { return test_packages; };
installer_package_installed = function(name) {
    for (let candidate in test_packages)
        if (candidate == name)
            return true;
    return false;
};
env = function(name, fallback) { return test_environment[name] || fallback || ""; };
path_executable = function(path) { return starts_with(path, "/etc/init.d/"); };
installer_command_result = function(args, seconds) {
    push(test_calls, join(" ", args));
    return {
        complete: true,
        status: args[0] == "apk" ? 0 : test_stop_status,
        output: args[0] == "apk" && args[3] == test_reverse_package ? test_reverse : ""
    };
};
run_args = function(args) {
    push(test_calls, join(" ", args));
    if (args[0] == "apk" && args[1] == "del") {
        if (args[2] == "--simulate") {
            test_plan = slice(args, 3);
            return true;
        }
        if (!test_remove_ok)
            return false;
        let remaining = [];
        for (let candidate in test_packages) {
            let remove = false;
            for (let name in slice(args, 2))
                if (name == candidate)
                    remove = true;
            if (!remove)
                push(remaining, candidate);
        }
        test_packages = remaining;
    }
    return true;
};
installer_recover_interrupted_cleanup = function(scripts) {};
installer_restore_dnsmasq = function(path, legacy) {
    push(test_calls, "restore-dns");
    return test_dns_ok;
};
remove_path = function(path) { push(test_calls, "cleanup " + path); return true; };
remove_globs = function(patterns) { push(test_calls, "cleanup-cache"); return true; };

test_packages = [ "sing-box-extended", "nextdns", "luci-app-passwall", "libc" ];
check(installer_full_suite_plan(true), "no-Forkop uninstall plan failed");
check(length(test_calls) == 0, "uninstall selected standalone VPN packages without Forkop");

test_packages = [ "forkop", "forkop-xray", "forkop-amneziawg", "luci-app-forkop", "luci-i18n-forkop-ru", "sing-box-extended", "nextdns", "luci-app-passwall", "another-app", "libc" ];
test_reverse = "another-app-1.0-r1";
check(installer_full_suite_plan(true), "shared sing-box prevented uninstalling Forkop");
check(join(" ", test_plan) == "forkop forkop-xray forkop-amneziawg luci-app-forkop luci-i18n-forkop-ru", "uninstall plan selected shared or unrelated packages");
test_reverse_package = "forkop";
test_calls = [];
check(!installer_full_suite_plan(true), "external dependency on Forkop accepted");
check(index(join(" ", test_calls), "apk del") < 0, "external dependency rejection changed packages");
test_reverse_package = "sing-box-extended";
test_environment.FORKOP_INSTALLER_REMOVE_PACKAGES = join(" ", test_plan);

test_calls = [];
test_stop_status = 1;
check(!installer_uninstall_suite(), "failed service stop accepted");
check(index(join(" ", test_calls), "apk del") < 0, "packages deleted after failed stop");
test_stop_status = 0;
test_calls = [];
test_dns_ok = false;
check(!installer_uninstall_suite(), "failed DNS restoration accepted");
check(index(join(" ", test_calls), "apk del") < 0, "packages deleted before DNS restoration");
test_dns_ok = true;
test_calls = [];
test_remove_ok = false;
check(!installer_uninstall_suite(), "failed package removal accepted");
check(index(join(" ", test_calls), "cleanup ") < 0, "settings deleted after package removal failure");
test_remove_ok = true;

test_calls = [];
check(installer_uninstall_suite(), "component uninstall failed");
check(join(" ", test_packages) == "sing-box-extended nextdns luci-app-passwall another-app libc", "shared or unrelated packages removed");
check(index(join(" ", test_calls), "/etc/init.d/sing-box stop") < 0, "shared sing-box stopped");
check(index(join(" ", test_calls), "/etc/init.d/nextdns") < 0, "unrelated DNS service stopped");
check(index(join(" ", test_calls), "cleanup /etc/config/forkop") >= 0, "Forkop settings not cleaned");
check(index(join(" ", test_calls), "/etc/sing-box") < 0, "shared sing-box settings changed");
check(index(join(" ", test_calls), "/etc/init.d/rpcd reload") >= 0, "LuCI cache not refreshed");
print("Embedded ucode uninstall checks passed\n");
