#!/usr/bin/env ucode

let fs = require("fs");
let uci_core = require("core.uci");
let common = require("core.common");
let read_json_file = common.read_json_file;
let runtime_dns = require("singbox.dns");
let runtime_awg = require("singbox.awg");
let selection = require("singbox.selection");
let core_version = require("singbox.version");

const CONFIG_NAME = getenv("ANTICHEBURNET_CONFIG_NAME") || "anticheburnet";
const LIB_DIR = getenv("ANTICHEBURNET_LIB") || "/usr/lib/anticheburnet";
const TMP_SING_BOX_FOLDER = getenv("TMP_SING_BOX_FOLDER") || "/tmp/sing-box";
const TMP_RULESET_FOLDER = getenv("TMP_RULESET_FOLDER") || TMP_SING_BOX_FOLDER + "/rulesets";
const TMP_SUBSCRIPTION_FOLDER = getenv("TMP_SUBSCRIPTION_FOLDER") || TMP_SING_BOX_FOLDER + "/subscriptions";
const RUNTIME_STATE_DIR = getenv("ANTICHEBURNET_RUNTIME_STATE_DIR") || "/var/run/anticheburnet";
const SUBSCRIPTION_UPDATE_STATE_DIR = getenv("ANTICHEBURNET_SUBSCRIPTION_UPDATE_STATE_DIR") || RUNTIME_STATE_DIR + "/subscription-update";
const SUBSCRIPTION_LINKS_DIR = getenv("ANTICHEBURNET_SUBSCRIPTION_LINKS_DIR") || RUNTIME_STATE_DIR + "/subscription-links";
const SUBSCRIPTION_METADATA_DIR = getenv("ANTICHEBURNET_SUBSCRIPTION_METADATA_DIR") || RUNTIME_STATE_DIR + "/subscription-metadata";
const OUTBOUND_METADATA_DIR = getenv("ANTICHEBURNET_OUTBOUND_METADATA_DIR") || RUNTIME_STATE_DIR + "/outbound-metadata";
const SECTION_CACHE_DIR = getenv("ANTICHEBURNET_SECTION_CACHE_DIR") || RUNTIME_STATE_DIR + "/section-cache";
const RUNTIME_CACHE_FORMAT_FILE = getenv("ANTICHEBURNET_RUNTIME_CACHE_FORMAT_FILE") || RUNTIME_STATE_DIR + "/cache-format";
const RUNTIME_CACHE_FORMAT = getenv("ANTICHEBURNET_RUNTIME_CACHE_FORMAT") || "8";
const PERSISTENT_SUBSCRIPTION_CACHE_DIR = getenv("ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_DIR") || "/etc/anticheburnet/subscription-cache";
const PERSISTENT_SUBSCRIPTION_CACHE_FORMAT_FILE = getenv("ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_FORMAT_FILE") || PERSISTENT_SUBSCRIPTION_CACHE_DIR + "/cache-format";
const PERSISTENT_SUBSCRIPTION_CACHE_FORMAT = getenv("ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_FORMAT") || "7";
const PENDING_RELOAD_FILE = getenv("ANTICHEBURNET_PENDING_RELOAD_FILE") || RUNTIME_STATE_DIR + "/reload.pending";
const SERVICE_INIT = getenv("ANTICHEBURNET_SERVICE_INIT") || "/etc/init.d/anticheburnet";
const NFT_TABLE_NAME = getenv("NFT_TABLE_NAME") || "AnticheburNETTable";
const NFT_COMMON_SET_NAME = getenv("NFT_COMMON_SET_NAME") || "anticheburnet_subnets";
const NFT_COMMON6_SET_NAME = getenv("NFT_COMMON6_SET_NAME") || "anticheburnet_subnets6";
const NFT_PORT_SET_NAME = getenv("NFT_PORT_SET_NAME") || "anticheburnet_ports";
const NFT_IP_PORT_SET_NAME = getenv("NFT_IP_PORT_SET_NAME") || "anticheburnet_ip_ports";
const NFT_IP_PORT6_SET_NAME = getenv("NFT_IP_PORT6_SET_NAME") || "anticheburnet_ip6_ports";
const NFT_INTERFACE_SET_NAME = getenv("NFT_INTERFACE_SET_NAME") || "anticheburnet_interfaces";
const NFT_LOCALV4_SET_NAME = getenv("NFT_LOCALV4_SET_NAME") || "localv4";
const NFT_LOCALV6_SET_NAME = getenv("NFT_LOCALV6_SET_NAME") || "localv6";
const NFT_FAKEIP_MARK = getenv("NFT_FAKEIP_MARK") || "0x04000000";
const SB_SERVICE_MIXED_INBOUND_ADDRESS = getenv("SB_SERVICE_MIXED_INBOUND_ADDRESS") || "127.0.0.1";
const SB_SERVICE_MIXED_INBOUND_PORT = getenv("SB_SERVICE_MIXED_INBOUND_PORT") || "4534";
const SB_VARIANT_STATE_FILE = getenv("SB_VARIANT_STATE_FILE") || "/etc/anticheburnet/sing-box-variant";
const SB_VERSION_STATE_FILE = getenv("SB_VERSION_STATE_FILE") || "/etc/anticheburnet/sing-box-version";
const SB_MANAGED_SERVICE_MARKER = getenv("SB_MANAGED_SERVICE_MARKER") || "AnticheburNET managed sing-box service for binary variants";

function as_string(value) {
    return value == null ? "" : "" + value;
}

function shell_quote(value) {
    return "'" + replace(as_string(value), /'/g, "'\\''") + "'";
}

function command_from_args(args) {
    let parts = [];
    for (let arg in args)
        push(parts, shell_quote(arg));
    return join(" ", parts);
}

function command_env(assignments) {
    let parts = [];
    for (let name, value in assignments)
        push(parts, name + "=" + shell_quote(value));
    return join(" ", parts);
}

function command_output(command) {
    let pipe = fs.popen(command, "r");
    if (!pipe)
        return "";

    let data = pipe.read("all");
    let status = pipe.close();
    if (status != 0 || data == null)
        return "";
    return as_string(data);
}

function command_output_from_args(args) {
    return command_output(command_from_args(args));
}

function command_status(command) {
    let status = int(system(command));
    return status > 255 ? int(status / 256) : status;
}

function command_success_from_args(args) {
    return system(command_from_args(args) + " >/dev/null 2>&1") == 0;
}

function command_exists(name) {
    return command_success_from_args([ "command", "-v", name ]);
}

function write_file(path, value) {
    return fs.writefile(as_string(path), as_string(value)) != null;
}

function remove_file(path) {
    try {
        fs.unlink(as_string(path));
    }
    catch (e) {
    }
}

function remove_files(paths) {
    for (let path in paths)
        if (as_string(path) != "")
            remove_file(path);
}

function file_first_line(path) {
    let data = fs.readfile(as_string(path));
    if (data == null)
        return "";
    let newline = index(data, "\n");
    return trim(newline >= 0 ? substr(data, 0, newline) : data);
}

function object_or_empty(value) {
    return type(value) == "object" ? value : {};
}

function array_or_empty(value) {
    return type(value) == "array" ? value : [];
}

function option(section, key, fallback) {
    if (fallback == null)
        fallback = "";

    let value = object_or_empty(section)[key];
    if (value == null)
        return fallback;
    if (type(value) == "array")
        return join(" ", value);
    return as_string(value);
}

function arg_bool(value) {
    value = lc(as_string(value));
    return value == "true" || value == "1" || value == "yes" || value == "on";
}

function bool_option(section, key, fallback) {
    let value = object_or_empty(section)[key];
    return value == null ? !!fallback : arg_bool(value);
}

function whitespace_items(value) {
    let result = [];
    if (type(value) == "array") {
        for (let item in value) {
            item = as_string(item);
            if (item != "")
                push(result, item);
        }
        return result;
    }

    for (let item in split(trim(as_string(value)), /[ \t\r\n]+/))
        if (item != "")
            push(result, item);
    return result;
}

function file_exists(path) {
    return fs.stat(as_string(path)) != null;
}

function parent_dir(path) {
    path = as_string(path);
    let slash = rindex(path, "/");
    return slash >= 0 ? substr(path, 0, slash) : "";
}

function ensure_dir(path) {
    return command_success_from_args([ "mkdir", "-p", path ]);
}

function ensure_parent_dir(path) {
    let dir = parent_dir(path);
    return dir == "" || dir == "." || ensure_dir(dir);
}

function temp_path() {
    return trim(command_output_from_args([ "mktemp" ]));
}

function md5_file(path) {
    let line = trim(command_output_from_args([ "md5sum", as_string(path) ]));
    return length(line) >= 32 ? substr(line, 0, 32) : "";
}

function first_line_last_field(value) {
    value = as_string(value);
    let newline = index(value, "\n");
    let line = trim(newline >= 0 ? substr(value, 0, newline) : value);
    let fields = split(line, /[ \t\r\n]+/);
    return length(fields) > 0 ? as_string(fields[length(fields) - 1]) : "";
}

function sing_box_version_output() {
    let info = core_version.get();
    if (info != null) return info.output;
    return command_exists("sing-box") ? command_output_from_args([ "sing-box", "version" ]) : "";
}

function sing_box_marker_is(value) {
    return file_first_line(SB_VARIANT_STATE_FILE) == as_string(value);
}

function sing_box_version_state() {
    return file_first_line(SB_VERSION_STATE_FILE);
}

function sing_box_write_version_state(version) {
    version = as_string(version);
    return version != "" && ensure_parent_dir(SB_VERSION_STATE_FILE) && write_file(SB_VERSION_STATE_FILE, version + "\n");
}

function sing_box_clear_version_state() {
    remove_file(SB_VERSION_STATE_FILE);
    return true;
}

function sing_box_restore_version_state(version) {
    version = as_string(version);
    return version != "" ? sing_box_write_version_state(version) : sing_box_clear_version_state();
}

function sing_box_variant_marker() {
    return file_first_line(SB_VARIANT_STATE_FILE);
}

function sing_box_write_variant_marker(variant) {
    variant = as_string(variant);
    return variant != "" && ensure_parent_dir(SB_VARIANT_STATE_FILE) && write_file(SB_VARIANT_STATE_FILE, variant + "\n");
}

function sing_box_clear_variant_marker() {
    remove_file(SB_VARIANT_STATE_FILE);
    return true;
}

function sing_box_restore_variant_marker(variant) {
    variant = as_string(variant);
    return variant != "" ? sing_box_write_variant_marker(variant) : sing_box_clear_variant_marker();
}

function sing_box_version() {
    let info = core_version.get();
    if (info != null) return info.version;
    if (fs.stat(getenv("ANTICHEBURNET_SING_BOX_BIN") || "/usr/bin/sing-box") != null)
        return "";
    if (!command_exists("sing-box"))
        return "";
    if (sing_box_marker_is("extended-compressed"))
        return sing_box_version_state();
    return first_line_last_field(sing_box_version_output());
}

function sing_box_version_is_extended(value) {
    return index(as_string(value), "extended") >= 0;
}

function sing_box_is_extended(value) {
    value = as_string(value);
    if (value == "" && command_exists("sing-box") && (sing_box_marker_is("extended-compressed") || sing_box_marker_is("extended")))
        return true;

    return sing_box_version_is_extended(value != "" ? value : sing_box_version());
}

function output_has_build_tag(output, tag) {
    tag = as_string(tag);
    if (tag == "")
        return false;

    for (let item in split(trim(replace(as_string(output), /[,: \t\r\n]+/g, " ")), " "))
        if (as_string(item) == tag)
            return true;
    return false;
}

function sing_box_supports_tailscale(version, version_output) {
    version = as_string(version);
    version_output = as_string(version_output);

    if (command_exists("sing-box") && sing_box_marker_is("extended-compressed"))
        return true;
    if (sing_box_is_extended(version))
        return true;
    if (version_output != "")
        return output_has_build_tag(version_output, "with_tailscale");
    return output_has_build_tag(sing_box_version_output(), "with_tailscale");
}

function module_command(args) {
    let command_args = [ "ucode", "-L", LIB_DIR ];
    for (let arg in args)
        push(command_args, arg);
    return command_from_args(command_args);
}

function module_success(args) {
    return command_status(module_command(args)) == 0;
}

function sing_box_package_installed(name) {
    return module_success([ LIB_DIR + "/core/packages.uc", "installed", as_string(name) ]);
}

function sing_box_is_tiny(version, version_output) {
    version = as_string(version);
    version_output = as_string(version_output);

    if (command_exists("sing-box") && sing_box_marker_is("extended-compressed"))
        return false;
    if (sing_box_is_extended(version != "" ? version : sing_box_version()))
        return false;
    if (sing_box_package_installed("sing-box-tiny"))
        return true;
    if (!sing_box_marker_is("tiny"))
        return false;
    return !sing_box_supports_tailscale(version, version_output);
}

function sing_box_variant() {
    let version = "";

    if (!command_exists("sing-box"))
        return "not-installed";
    if (sing_box_marker_is("extended-compressed"))
        return "extended-compressed";

    version = sing_box_version();
    if (sing_box_is_extended(version))
        return sing_box_marker_is("extended-compressed") ? "extended-compressed" : "extended";
    if (sing_box_is_tiny(version, ""))
        return "tiny";
    return "stable";
}

function log_message(message, level) {
    level = as_string(level || "info");
    command_success_from_args([ "logger", "-t", "anticheburnet", "[" + level + "] " + as_string(message) ]);
}

function module_env_capture(env, args) {
    let output_path = temp_path();
    if (output_path == "")
        return { status: 1, output: "" };

    let status = command_status(command_env(env) + " " + module_command(args) + " >" + shell_quote(output_path) + " 2>&1");
    let output = as_string(fs.readfile(output_path) || "");
    remove_file(output_path);
    return { status, output };
}

function uci_settings() {
    return object_or_empty(uci_core.get_all(CONFIG_NAME, "settings"));
}

function uci_path(config, section, key) {
    return as_string(config) + "." + as_string(section) + "." + as_string(key);
}

function uci_get_option(config, section, key) {
    return trim(uci_core.get(uci_path(config, section, key)));
}

function ensure_sing_box_main_section() {
    if (uci_core.exists("sing-box.main"))
        return true;
    return uci_core.set_section("sing-box.main", "sing-box");
}

function uci_set_option(config, section, key, value) {
    if (!uci_core.exists(as_string(config) + "." + as_string(section)))
        return false;
    return uci_core.set(uci_path(config, section, key), value);
}

function uci_commit(config) {
    return uci_core.commit(config);
}

function owner_pid() {
    let pid = trim(command_output_from_args([ "sh", "-c", "echo $PPID" ]));
    return match(pid, /^[0-9]+$/) != null ? pid : "0";
}

function managed_service_installed() {
    let data = fs.readfile("/etc/init.d/sing-box");
    return data != null && index(as_string(data), SB_MANAGED_SERVICE_MARKER) >= 0;
}

function managed_service_text() {
    // sing-box persists the FakeIP allocator metadata during graceful shutdown.
    // Give large configurations more than procd's five-second default before SIGKILL.
    return "#!/bin/sh /etc/rc.common\n" +
        "# " + SB_MANAGED_SERVICE_MARKER + "\n\n" +
        "USE_PROCD=1\n" +
        "START=99\n" +
        "PROG=\"/usr/bin/sing-box\"\n\n" +
        "start_service() {\n" +
        "    config_load \"sing-box\"\n" +
        "    local enabled config_file working_directory\n" +
        "    local log_stderr\n\n" +
        "    config_get_bool enabled \"main\" \"enabled\" \"0\"\n" +
        "    [ \"$enabled\" -eq \"1\" ] || return 0\n\n" +
        "    config_get config_file \"main\" \"conffile\" \"/etc/sing-box/config.json\"\n" +
        "    config_get working_directory \"main\" \"workdir\" \"/usr/share/sing-box\"\n" +
        "    config_get_bool log_stderr \"main\" \"log_stderr\" \"1\"\n\n" +
        "    procd_open_instance\n" +
        "    procd_set_param command \"$PROG\" run -c \"$config_file\" -D \"$working_directory\"\n" +
        "    procd_set_param file \"$config_file\"\n" +
        "    procd_set_param stderr \"$log_stderr\"\n" +
        "    procd_set_param limits core=\"unlimited\"\n" +
        "    procd_set_param limits nofile=\"1000000 1000000\"\n" +
        "    procd_set_param term_timeout 30\n" +
        "    procd_set_param respawn\n" +
        "    procd_close_instance\n" +
        "}\n\n" +
        "service_triggers() {\n" +
        "    procd_add_reload_trigger \"sing-box\"\n" +
        "}\n";
}

function sing_box_compressed_marker_set() {
    return trim(as_string(fs.readfile(SB_VARIANT_STATE_FILE) || "")) == "extended-compressed";
}

function install_managed_service_script() {
    let tmp = "/etc/init.d/sing-box.anticheburnet." + owner_pid();
    if (!write_file(tmp, managed_service_text()))
        return false;
    if (!command_success_from_args([ "chmod", "0755", tmp ])) {
        remove_file(tmp);
        return false;
    }
    return fs.rename(tmp, "/etc/init.d/sing-box");
}

function remove_managed_service_script() {
    if (!managed_service_installed())
        return;

    command_success_from_args([ "/etc/init.d/sing-box", "stop" ]);
    command_success_from_args([ "/etc/init.d/sing-box", "disable" ]);
    remove_file("/etc/init.d/sing-box");
}

function disable_service_config() {
    if (!ensure_sing_box_main_section())
        return;
    uci_set_option("sing-box", "main", "enabled", "0");
    uci_commit("sing-box");
}

function prepare_service_disabled() {
    disable_service_config();
    if (file_exists("/etc/init.d/sing-box")) {
        command_success_from_args([ "/etc/init.d/sing-box", "stop" ]);
        command_success_from_args([ "/etc/init.d/sing-box", "disable" ]);
    }
}

function configure_service() {
    let settings = uci_settings();

    if (sing_box_compressed_marker_set() && !install_managed_service_script()) {
        log_message("Failed to install managed sing-box service for compressed binary. Aborted.", "fatal");
        exit(1);
    }

    if (!ensure_sing_box_main_section())
        exit(1);

    let changed = false;
    if (uci_get_option("sing-box", "main", "enabled") != "1") {
        if (!uci_set_option("sing-box", "main", "enabled", "1"))
            exit(1);
        changed = true;
        log_message("sing-box service has been enabled", "info");
    }

    if (uci_get_option("sing-box", "main", "user") != "root") {
        if (!uci_set_option("sing-box", "main", "user", "root"))
            exit(1);
        changed = true;
        log_message("sing-box service user has been changed to root", "info");
    }

    let config_path = option(settings, "config_path", "");
    let conffile = uci_get_option("sing-box", "main", "conffile");
    if (conffile != config_path) {
        if (!uci_set_option("sing-box", "main", "conffile", config_path))
            exit(1);
        changed = true;
        log_message("sing-box service config path set to " + config_path, "info");
    }

    if (changed && !uci_commit("sing-box"))
        exit(1);

    if (file_exists("/etc/rc.d/S99sing-box")) {
        log_message("Disabling standalone sing-box autostart", "info");
        command_success_from_args([ "/etc/init.d/sing-box", "disable" ]);
    }
}

function download_via_proxy_option_for_purpose(purpose) {
    purpose = as_string(purpose || "lists");
    if (purpose == "lists")
        return "download_lists_via_proxy";
    if (purpose == "components")
        return "download_components_via_proxy";
    return "";
}

function download_via_proxy_section_option_for_purpose(purpose) {
    purpose = as_string(purpose || "lists");
    if (purpose == "lists")
        return "download_lists_via_proxy_section";
    if (purpose == "components")
        return "download_components_via_proxy_section";
    return "";
}

function download_via_proxy_section(settings, purpose) {
    let enabled_option = download_via_proxy_option_for_purpose(purpose);
    if (enabled_option == "" || !bool_option(settings, enabled_option, false))
        return "";

    let section_option = download_via_proxy_section_option_for_purpose(purpose);
    let configured = section_option != "" ? option(settings, section_option, "") : "";
    if (configured != "")
        return configured;

    return option(settings, "download_lists_via_proxy_section", "");
}

function service_proxy_port_for_purpose(purpose) {
    return int(SB_SERVICE_MIXED_INBOUND_PORT) + (as_string(purpose || "lists") == "components" ? 1 : 0);
}

function service_proxy_address(settings, purpose) {
    return download_via_proxy_section(settings, purpose) != "" ?
        SB_SERVICE_MIXED_INBOUND_ADDRESS + ":" + service_proxy_port_for_purpose(purpose) : "";
}

function ip_addr_first_inet4(data) {
    for (let line in split(as_string(data), "\n")) {
        let matched = match(line, /inet[ \t]+([0-9.]+)\//);
        if (matched)
            return as_string(matched[1]);
    }
    return "";
}

function network_interface_ipv4(name) {
    let data = command_output_from_args([ "ubus", "call", "network.interface." + as_string(name), "status" ]);
    try {
        let value = json(data);
        let addresses = array_or_empty(object_or_empty(value)["ipv4-address"]);
        if (length(addresses) > 0)
            return as_string(object_or_empty(addresses[0]).address);
    }
    catch (e) {
    }
    return "";
}

function device_ipv4_address_value(device) {
    return ip_addr_first_inet4(command_output_from_args([ "ip", "-4", "addr", "show", "dev", as_string(device) ]));
}

function service_listen_address_value(settings) {
    let configured = option(settings, "service_listen_address", "");
    if (configured != "") {
        log_message("service_listen_address is set manually; automatic listen-address detection is skipped", "warn");
        return configured;
    }

    let address = network_interface_ipv4("lan");
    if (address != "")
        return address;

    for (let iface in whitespace_items(option(settings, "source_network_interfaces", "br-lan"))) {
        address = network_interface_ipv4(iface);
        if (address != "")
            return address;
        address = device_ipv4_address_value(iface);
        if (address != "")
            return address;
    }

    log_message("Failed to determine the listening IP address. Please open an issue to report this problem: https://github.com/m-bezrukoff/AnticheburNET/issues", "error");
    return "";
}

function subscription_cache_env() {
    return {
        ANTICHEBURNET_CONFIG_NAME: CONFIG_NAME,
        ANTICHEBURNET_LIB: LIB_DIR,
        TMP_SING_BOX_FOLDER,
        TMP_RULESET_FOLDER,
        TMP_SUBSCRIPTION_FOLDER,
        ANTICHEBURNET_RUNTIME_STATE_DIR: RUNTIME_STATE_DIR,
        ANTICHEBURNET_SUBSCRIPTION_UPDATE_STATE_DIR: SUBSCRIPTION_UPDATE_STATE_DIR,
        ANTICHEBURNET_SUBSCRIPTION_LINKS_DIR: SUBSCRIPTION_LINKS_DIR,
        ANTICHEBURNET_SUBSCRIPTION_METADATA_DIR: SUBSCRIPTION_METADATA_DIR,
        ANTICHEBURNET_OUTBOUND_METADATA_DIR: OUTBOUND_METADATA_DIR,
        ANTICHEBURNET_SECTION_CACHE_DIR: SECTION_CACHE_DIR,
        ANTICHEBURNET_RUNTIME_CACHE_FORMAT_FILE: RUNTIME_CACHE_FORMAT_FILE,
        ANTICHEBURNET_RUNTIME_CACHE_FORMAT: RUNTIME_CACHE_FORMAT,
        ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_DIR: PERSISTENT_SUBSCRIPTION_CACHE_DIR,
        ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_FORMAT_FILE: PERSISTENT_SUBSCRIPTION_CACHE_FORMAT_FILE,
        ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_FORMAT: PERSISTENT_SUBSCRIPTION_CACHE_FORMAT,
        ANTICHEBURNET_PENDING_RELOAD_FILE: PENDING_RELOAD_FILE,
        ANTICHEBURNET_SERVICE_INIT: SERVICE_INIT
    };
}

function subscription_cache_capture(args) {
    let command_args = [ LIB_DIR + "/subscription/cache.uc" ];
    for (let arg in args)
        push(command_args, arg);
    return module_env_capture(subscription_cache_env(), command_args);
}

function log_lines(text, level, prefix) {
    for (let line in split(as_string(text), "\n"))
        if (trim(as_string(line)) != "")
            log_message(as_string(prefix) + as_string(line), level);
}

function first_nonblank_line(path) {
    let data = as_string(fs.readfile(path) || "");
    for (let line in split(data, "\n"))
        if (trim(as_string(line)) != "")
            return as_string(line);
    return "";
}

function last_nonblank_line(path) {
    let result = "";
    let data = as_string(fs.readfile(path) || "");
    for (let line in split(data, "\n"))
        if (trim(as_string(line)) != "")
            result = as_string(line);
    return result;
}

function generator_failure_reason(path, status) {
    let reason = last_nonblank_line(path);
    return reason != "" ? reason : "exit status " + status;
}

function log_file_lines(path, level, prefix) {
    log_lines(fs.readfile(path), level, prefix);
}

function sing_box_check(config_path, output_path) {
    let status = command_status(
        command_from_args([ "sing-box", "-c", config_path, "check" ]) +
        " >" + shell_quote(output_path) + " 2>&1"
    );
    let reason = status == 0 ? "" : first_nonblank_line(output_path);
    if (status != 0 && reason == "")
        reason = "exit status " + status;
    return { status, reason };
}

function prepare_subscription_caches(prepared, no_refresh) {
    let result = subscription_cache_capture([ "prepare-caches", "runtime", prepared ? "1" : "0", no_refresh ? "1" : "0" ]);
    if (result.status != 0) {
        log_message("Subscription caches are not ready for sing-box config generation. Aborted.", "fatal");
        log_lines(result.output, "debug", "subscription cache: ");
        return null;
    }
    return trim(result.output);
}

function save_config_file(temp_file_path, config_path) {
    let current_hash = md5_file(config_path);
    let temp_hash = md5_file(temp_file_path);

    if (current_hash != temp_hash) {
        log_message("sing-box configuration changed; updating " + config_path, "info");
        if (!ensure_parent_dir(config_path))
            return false;
        return command_success_from_args([ "mv", "-f", temp_file_path, config_path ]);
    }

    log_message("sing-box configuration is unchanged", "info");
    remove_file(temp_file_path);
    return true;
}

function replace_dns_server(config, replacement) {
    let servers = array_or_empty(object_or_empty(config.dns).servers);
    for (let i = 0; i < length(servers); i++) {
        if (as_string(object_or_empty(servers[i]).tag) == as_string(replacement.tag)) {
            servers[i] = replacement;
            return true;
        }
    }
    return false;
}

function patch_dns_config(state_path) {
    let settings = uci_settings();
    let candidate_state = common.read_json_file(state_path);
    let expected = runtime_dns.state_template(settings);
    if (!runtime_dns.state_matches(expected, candidate_state)) {
        log_message("DNS failover state does not match the current UCI configuration", "warn");
        exit(2);
    }

    let config_path = option(settings, "config_path", "");
    let config = common.read_json_file(config_path);
    if (config_path == "" || type(config) != "object") {
        log_message("Cannot read the current sing-box configuration for DNS failover", "error");
        exit(1);
    }

    let main = runtime_dns.server_config(settings, candidate_state);
    let bootstrap = runtime_dns.bootstrap_config(settings, candidate_state);
    if (main.unsupported || !replace_dns_server(config, main) || !replace_dns_server(config, bootstrap)) {
        log_message("Cannot locate or build canonical DNS servers for failover", "error");
        exit(1);
    }

    let backup_path = temp_path();
    let temp_config = temp_path();
    if (backup_path == "" || temp_config == "" ||
        fs.writefile(backup_path, fs.readfile(config_path)) == null ||
        !common.write_json_file(temp_config, config)) {
        remove_files([ backup_path, temp_config ]);
        exit(1);
    }

    let check_log = temp_path();
    let check_result = check_log == ""
        ? { status: 1, reason: "unable to create check output file" }
        : sing_box_check(temp_config, check_log);
    if (check_result.status != 0) {
        log_message("DNS failover produced an invalid sing-box configuration: " + check_result.reason, "error");
        remove_files([ backup_path, temp_config, check_log ]);
        exit(1);
    }
    remove_file(check_log);

    let changed = md5_file(config_path) != md5_file(temp_config);
    if (!save_config_file(temp_config, config_path)) {
        remove_file(backup_path);
        exit(1);
    }

    if (!changed) {
        remove_file(backup_path);
        print("0\n");
        return;
    }

    print("1\t", backup_path, "\n");
}

function restore_dns_config(backup_path) {
    let config_path = option(uci_settings(), "config_path", "");
    if (config_path == "" || !file_exists(backup_path))
        return false;
    return command_success_from_args([ "mv", "-f", backup_path, config_path ]);
}

function managed_provider(config) {
    for (let provider in array_or_empty(object_or_empty(config).providers))
        if (provider.type == "anticheburnet" && provider.tag == "anticheburnet-subscriptions")
            return provider;
    return null;
}

function canonical_value(value) {
    if (type(value) == "array") {
        let result = [];
        for (let item in value) push(result, canonical_value(item));
        return result;
    }
    if (type(value) != "object") return value;
    let result = {}, names = keys(value);
    sort(names);
    for (let name in names) result[name] = canonical_value(value[name]);
    return result;
}

function provider_update_compatible(current, candidate) {
    if (managed_provider(current) == null || managed_provider(candidate) == null)
        return false;
    let old = read_json_file(managed_provider(current).path);
    let fresh = read_json_file(managed_provider(candidate).path);
    if (type(old) != "object" || type(fresh) != "object" ||
        type(old.configuration) != "object" || type(fresh.configuration) != "object" ||
        type(fresh.outbounds) != "array" || length(fresh.outbounds) == 0)
        return false;
    return sprintf("%J", canonical_value(old.configuration)) == sprintf("%J", canonical_value(fresh.configuration));
}

function install_provider_file(temp_config, config_path) {
    let config = read_json_file(temp_config);
    let provider = managed_provider(config);
    if (provider == null) return true;
    let path = config_path + ".providers.json";
    if (!save_config_file(provider.path, path)) return false;
    provider.path = path;
    return fs.writefile(temp_config, sprintf("%J\n", config)) != null;
}

function init_config(populate_nft, caches_prepared, no_refresh, prepared_deferred_sections) {
    let settings = uci_settings();
    let config_path = option(settings, "config_path", "");
    if (config_path == "") {
        log_message("sing-box config path is empty. Aborted.", "fatal");
        exit(1);
    }

    let mwan3_active = module_success([ LIB_DIR + "/config/validator.uc", "mwan3-is-active" ]);
    let output_interface = option(settings, "output_network_interface", "");
    if (mwan3_active && output_interface != "")
        log_message("mwan3 is active and Output Network Interface is set to '" + output_interface + "'; sing-box egress is pinned to this interface", "warn");
    else if (mwan3_active)
        log_message("mwan3 is active; disabling sing-box auto_detect_interface so mwan3 can control egress routing", "warn");

    let deferred_sections = trim(as_string(prepared_deferred_sections));
    if (deferred_sections == "") {
        deferred_sections = prepare_subscription_caches(caches_prepared, no_refresh);
        if (deferred_sections == null)
            exit(1);
    }

    let temp_config = temp_path();
    let runtime_log = temp_path();
    if (temp_config == "" || runtime_log == "") {
        remove_files([ temp_config, temp_config + ".awg.json", runtime_log ]);
        exit(1);
    }

    let generate_status = command_status(
        module_command([
            LIB_DIR + "/singbox/generator.uc",
            "generate-config",
            temp_config,
            service_listen_address_value(settings),
            mwan3_active ? "1" : "0",
            sing_box_is_extended(sing_box_version()) ? "1" : "0",
            deferred_sections,
            sing_box_version()
        ]) + " >" + shell_quote(runtime_log) + " 2>&1"
    );
    if (generate_status != 0) {
        let reason = generator_failure_reason(runtime_log, generate_status);
        log_message("Failed to generate sing-box configuration: " + reason, "fatal");
        remove_files([ temp_config, temp_config + ".awg.json", runtime_log ]);
        exit(1);
    }
    log_file_lines(runtime_log, "warn", "sing-box config generator: ");

    let check_result = sing_box_check(temp_config, runtime_log);
    if (check_result.status != 0) {
        log_message("Generated sing-box configuration is invalid: " + check_result.reason + ". Aborted.", "fatal");
        remove_files([ temp_config, temp_config + ".awg.json", runtime_log ]);
        exit(1);
    }

    if (populate_nft && !module_success([
        LIB_DIR + "/nft/apply.uc",
        "nft-populate-runtime-sets-from-uci",
        "1",
        deferred_sections,
        NFT_TABLE_NAME,
        NFT_COMMON_SET_NAME,
        NFT_PORT_SET_NAME,
        NFT_IP_PORT_SET_NAME,
        NFT_INTERFACE_SET_NAME,
        NFT_LOCALV4_SET_NAME,
        NFT_FAKEIP_MARK,
        NFT_COMMON6_SET_NAME,
        NFT_IP_PORT6_SET_NAME,
        NFT_LOCALV6_SET_NAME
    ])) {
        log_message("Failed to update nftables runtime sets from the generated sing-box configuration. Aborted.", "fatal");
        remove_files([ temp_config, temp_config + ".awg.json", runtime_log ]);
        exit(1);
    }

    if (!install_provider_file(temp_config, config_path) || !save_config_file(temp_config, config_path)) {
        remove_file(temp_config + ".awg.json");
        remove_file(runtime_log);
        exit(1);
    }
    if (!save_config_file(temp_config + ".awg.json", config_path + ".awg.json")) {
        remove_file(runtime_log);
        log_message("Failed to save native AWG subscription profiles. Aborted.", "fatal");
        exit(1);
    }
    // Subscription updates rebuild directly through this owner, bypassing the
    // main lifecycle reload path. Apply native profiles here in every case.
    if (!runtime_awg.sync(config_path + ".awg.json")) {
        remove_file(runtime_log);
        log_message("Native AWG subscription interfaces are not ready. Aborted.", "fatal");
        exit(1);
    }
    remove_file(runtime_log);
    print(deferred_sections, "\n");
}

function remove_provider_stage(path) {
    remove_files([ path, path + ".awg.json", path + ".providers.json", path + ".log" ]);
    for (let item in fs.glob(path + ".section-cache/*.json")) remove_file(item);
    fs.rmdir(path + ".section-cache");
}

function update_providers(only_if_pending) {
    let settings = uci_settings();
    let config_path = option(settings, "config_path", "");
    let pending_path = config_path + ".providers.pending";
    if (only_if_pending && fs.stat(pending_path) == null) return true;
    if (config_path == "" || fs.writefile(pending_path, "pending\n") == null) return false;
    let current = read_json_file(config_path);
    let provider = managed_provider(current);
    if (provider == null) {
        log_message("Dynamic providers are not active. Install the current sing-box component and Apply configuration once; subscription update will not restart services", "error");
        return false;
    }
    let candidate_path = temp_path();
    if (candidate_path == "") return false;
    if (!runtime_awg.write_private(candidate_path + ".log", "")) {
        remove_provider_stage(candidate_path);
        return false;
    }
    let stage_dir = candidate_path + ".section-cache";
    if (!ensure_dir(stage_dir)) { remove_provider_stage(candidate_path); return false; }
    for (let path in fs.glob(SECTION_CACHE_DIR + "/*.json"))
        command_success_from_args([ "cp", path, stage_dir + "/" + split(path, "/")[-1] ]);
    let command = "ANTICHEBURNET_SECTION_CACHE_DIR=" + shell_quote(stage_dir) + " " + module_command([
        LIB_DIR + "/singbox/generator.uc", "generate-config", candidate_path,
        service_listen_address_value(settings),
        module_success([ LIB_DIR + "/config/validator.uc", "mwan3-is-active" ]) ? "1" : "0",
        "1", "", sing_box_version()
    ]);
    if (command_status(command + " >" + shell_quote(candidate_path + ".log") + " 2>&1") != 0) {
        log_message("Failed to prepare dynamic providers; keeping the running graph", "error");
        log_file_lines(candidate_path + ".log", "warn", "provider generator: ");
        remove_provider_stage(candidate_path);
        return false;
    }
    let candidate = read_json_file(candidate_path);
    if (!provider_update_compatible(current, candidate)) {
        log_message("Subscription routing changed; Apply configuration is required. Running services were preserved", "error");
        remove_provider_stage(candidate_path);
        return false;
    }
    let manifest_path = config_path + ".awg.json";
    let candidate_provider_path = managed_provider(candidate).path;
    let old_payload = fs.readfile(provider.path);
    let payload = read_json_file(candidate_provider_path);
    let awg_plan;
    try {
        awg_plan = runtime_awg.plan_update(runtime_awg.profiles(manifest_path),
            runtime_awg.profiles(candidate_path + ".awg.json"), payload.outbounds);
    }
    catch (error) {
        log_message("Unable to prepare native AWG subscription update; running interfaces were preserved", "error");
        remove_provider_stage(candidate_path);
        return false;
    }
    // Start only new native instances before publishing their proxy references.
    // Existing instances retain their slots, processes and connections.
    if (old_payload == null || !runtime_awg.write_private(candidate_provider_path, sprintf("%J\n", payload)) ||
        !runtime_awg.begin_update(manifest_path, awg_plan)) {
        log_message("Native AWG subscription preparation failed; running provider was preserved", "error");
        remove_provider_stage(candidate_path);
        return false;
    }
    // The provider validates constructors, references, cycles and startup in an
    // isolated graph before atomically publishing it. No external check/reload.
    let selected_profiles = selection.capture();
    if (selected_profiles == null) {
        runtime_awg.rollback_update(manifest_path, awg_plan);
        remove_provider_stage(candidate_path);
        log_message("Unable to capture selected connection profiles; provider update remains pending", "error");
        return false;
    }
    if (!save_config_file(candidate_provider_path, provider.path)) {
        if (!runtime_awg.rollback_update(manifest_path, awg_plan))
            log_message("Native AWG cleanup remains pending after provider file failure", "error");
        remove_provider_stage(candidate_path);
        return false;
    }
    let revision = substr(trim(command_output_from_args([ "sha256sum", provider.path ])), 0, 64);
    if (!module_success([ LIB_DIR + "/diagnostics/runtime.uc", "clash-api", "update_provider", provider.tag, revision ])) {
        let rollback_path = candidate_path + ".providers.json";
        if (!runtime_awg.write_private(rollback_path, old_payload) || !fs.rename(rollback_path, provider.path)) {
            log_message("Provider confirmation failed and the previous file could not be restored", "error");
            remove_provider_stage(candidate_path);
            return false;
        }
        let old_revision = substr(trim(command_output_from_args([ "sha256sum", provider.path ])), 0, 64);
        let restored = module_success([ LIB_DIR + "/diagnostics/runtime.uc", "clash-api", "update_provider", provider.tag, old_revision ]);
        // With an uncertain API outcome either graph may still be live. Keep
        // both sets of native interfaces until a retry confirms the provider.
        if (restored && !selection.restore(selected_profiles))
            log_message("Previous provider restored but connection selection could not be restored", "error");
        if (restored && !runtime_awg.rollback_update(manifest_path, awg_plan))
            log_message("Previous provider confirmed but native AWG cleanup remains pending", "error");
        log_message(restored ? "Dynamic provider update failed; previous graph restored and confirmed" : "Dynamic provider update could not be confirmed; previous file restored and retry remains pending", "error");
        remove_provider_stage(candidate_path);
        return false;
    }
    let ok = selection.restore(selected_profiles);
    if (!ok) log_message("Provider applied but selected connection profiles could not be restored", "error");
    if (!runtime_awg.commit_update(manifest_path, awg_plan)) ok = false;
    if (!ok) log_message("Provider applied but native AWG cleanup remains pending", "error");
    for (let path in fs.glob(stage_dir + "/*.json"))
        if (!fs.rename(path, SECTION_CACHE_DIR + "/" + split(path, "/")[-1])) ok = false;
    remove_provider_stage(candidate_path);
    if (ok) remove_file(pending_path);
    if (!ok) log_message("Provider applied but subscription finalization remains pending", "error");
    return ok;
}

let mode = ARGV[0] || "";

if (mode == "configure-service")
    configure_service();
else if (mode == "init-config")
    init_config(arg_bool(ARGV[1] || "1"), arg_bool(ARGV[2] || "0"), arg_bool(ARGV[3] || "0"), ARGV[4] || "");
else if (mode == "update-providers")
    exit(update_providers(arg_bool(ARGV[1] || "0")) ? 0 : 1);
else if (mode == "provider-update-compatible-fixture")
    exit(provider_update_compatible(read_json_file(ARGV[1]), read_json_file(ARGV[2])) ? 0 : 1);
else if (mode == "save-config-file-fixture")
    exit(save_config_file(ARGV[1] || "", ARGV[2] || "") ? 0 : 1);
else if (mode == "check-config-fixture") {
    let result = sing_box_check(ARGV[1] || "", ARGV[2] || "");
    if (result.reason != "")
        print(result.reason, "\n");
    exit(result.status);
}
else if (mode == "generator-failure-reason-fixture")
    print(generator_failure_reason(ARGV[1] || "", int(ARGV[2] || "1")), "\n");
else if (mode == "patch-dns-config")
    patch_dns_config(ARGV[1] || "");
else if (mode == "restore-dns-config")
    exit(restore_dns_config(ARGV[1] || "") ? 0 : 1);
else if (mode == "managed-service-installed")
    exit(managed_service_installed() ? 0 : 1);
else if (mode == "remove-managed-service-script")
    remove_managed_service_script();
else if (mode == "prepare-service-disabled")
    prepare_service_disabled();
else if (mode == "service-proxy-address")
    print(service_proxy_address(uci_settings(), ARGV[1] || "lists"), "\n");
else if (mode == "service-listen-address") {
    let address = service_listen_address_value(uci_settings());
    if (address == "")
        exit(1);
    print(address, "\n");
}
else if (mode == "device-ipv4-address") {
    let address = device_ipv4_address_value(ARGV[1]);
    if (address == "")
        exit(1);
    print(address, "\n");
}
else if (mode == "ip-addr-first-inet4")
    print(ip_addr_first_inet4(fs.readfile("/dev/stdin")), "\n");
else if (mode == "version")
    print(sing_box_version(), "\n");
else if (mode == "version-output")
    print(sing_box_version_output());
else if (mode == "version-from-output")
    print(first_line_last_field(fs.readfile("/dev/stdin")), "\n");
else if (mode == "read-version-state")
    print(sing_box_version_state(), "\n");
else if (mode == "write-version-state")
    exit(sing_box_write_version_state(ARGV[1]) ? 0 : 1);
else if (mode == "clear-version-state")
    exit(sing_box_clear_version_state() ? 0 : 1);
else if (mode == "restore-version-state")
    exit(sing_box_restore_version_state(ARGV[1]) ? 0 : 1);
else if (mode == "read-variant-marker")
    print(sing_box_variant_marker(), "\n");
else if (mode == "write-variant-marker")
    exit(sing_box_write_variant_marker(ARGV[1]) ? 0 : 1);
else if (mode == "clear-variant-marker")
    exit(sing_box_clear_variant_marker() ? 0 : 1);
else if (mode == "restore-variant-marker")
    exit(sing_box_restore_variant_marker(ARGV[1]) ? 0 : 1);
else if (mode == "marker-is")
    exit(sing_box_marker_is(ARGV[1]) ? 0 : 1);
else if (mode == "is-extended")
    exit(sing_box_is_extended(ARGV[1]) ? 0 : 1);
else if (mode == "is-tiny")
    exit(sing_box_is_tiny(ARGV[1], ARGV[2]) ? 0 : 1);
else if (mode == "supports-tailscale")
    exit(sing_box_supports_tailscale(ARGV[1], ARGV[2]) ? 0 : 1);
else if (mode == "variant")
    print(sing_box_variant(), "\n");
else {
    warn("Usage: singbox/runtime.uc <operation> ...\n");
    exit(1);
}
