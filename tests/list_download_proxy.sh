#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
LIB="$ROOT_DIR/anticheburnet/files/usr/lib"
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$LIB/components/updates.uc" >"$WORK_DIR/download.uc"
cat >>"$WORK_DIR/download.uc" <<'UC'
function assert(value, label) {
    if (!value) die(label + "\n");
}
function argument(args, name) {
    let pos = index(args, name);
    assert(pos >= 0 && pos + 1 < length(args), "Missing " + name);
    return args[pos + 1];
}
let requests = [], sleeps = 0, logs = [], failures = 0;
log_message = function(message, level) { push(logs, { message, level }); };
command_success = function(command) {
    die("List download used the legacy wget shell path\n");
};
command_success_from_args = function(args) {
    if (args[0] == "sleep") { sleeps++; return true; }
    assert(args[0] == "curl", "List downloads must support HTTPS CONNECT");
    assert(args[1] == "-q", "curl config must not override download routing");
    assert(index(args, "-fL") >= 0, "HTTP errors must fail and redirects must be followed");
    assert(argument(args, "--noproxy") == "", "NO_PROXY must not bypass the selected tunnel");
    assert(int(argument(args, "--connect-timeout")) > 0, "Connect timeout required");
    assert(int(argument(args, "--max-time")) > 0, "Total timeout required");
    assert(args[length(args) - 2] == "--", "URL must be separated from options");
    push(requests, args);
    if (failures > 0) { failures--; return false; }
    fs.writefile(argument(args, "-o"), "203.0.113.0/24\n");
    return true;
};
let output = ARGV[1];
let settings = { download_lists_via_proxy: "1", download_lists_via_proxy_section: "tunnel" };
let proxy = service_proxy_address(settings, "lists");
assert(proxy != "", "Enabled list tunnel must resolve to a service proxy");
assert(download_to_file("https://example.com/list.lst", output, proxy), "HTTPS proxy download failed");
assert(argument(requests[0], "--proxy") == "http://" + proxy, "Explicit proxy required");
assert(file_nonempty(output), "Successful download must produce a list");

settings.download_lists_via_proxy = "0";
assert(download_to_file("https://example.com/direct.lst", output, service_proxy_address(settings, "lists")), "Direct download failed");
assert(argument(requests[1], "--proxy") == "", "Direct download must ignore ambient proxy variables");

requests = []; sleeps = 0; failures = 2;
assert(download_to_file("https://example.com/retry.lst", output, proxy), "Retry did not recover");
assert(length(requests) == 3 && sleeps == 2, "Expected three attempts with two retry delays");
for (let args in requests)
    assert(argument(args, "--proxy") == "http://" + proxy, "Retry bypassed tunnel");

requests = []; failures = 3;
assert(!download_to_file("https://example.com/fail.lst", output, proxy), "Permanent failure must be reported");
assert(length(requests) == 3, "Retries must be bounded");
for (let args in requests)
    assert(argument(args, "--proxy") == "http://" + proxy, "Failed tunnel must not fall back to direct");

// Exercise both built-in Discord families through the real import path.
requests = []; failures = 0; logs = []; settings.download_lists_via_proxy = "1";
let imports = 0, removed = 0;
temp_path = function() { return output; };
remove_file = function(path) { removed++; fs.unlink(path); };
nft_module_success = function(args) {
    assert(args[0] == "nft-add-community-subnet-file-for-uci-section", "Unexpected import");
    assert(args[2] == "discord" && file_nonempty(args[3]), "Discord subnet file missing");
    imports++; return true;
};
let section = { ".name": "discord_rule", enabled: "1", action: "proxy", community_lists: [ "discord" ] };
assert(import_builtin_subnets_from_rule(section, settings), "Built-in Discord import failed");
assert(length(requests) == 2 && imports == 2 && removed == 2, "Both Discord address families must be imported and cleaned up");
for (let args in requests)
    assert(argument(args, "--proxy") == "http://" + proxy, "Built-in list bypassed tunnel");

requests = []; imports = 0; failures = 6;
assert(!import_builtin_subnets_from_rule(section, settings), "Failed built-in downloads must fail update");
assert(length(requests) == 6 && imports == 0, "Failed lists must not reach nft import");
let errors = 0;
for (let entry in logs)
    if (entry.level == "error") {
        errors++;
        assert(index(entry.message, "https://") >= 0, "Failure must identify the list URL");
    }
assert(errors == 2, "Each failed Discord family must be reported");
print("List download proxy checks passed\n");
UC
ucode -L "$LIB" "$WORK_DIR/download.uc" test "$WORK_DIR/list.lst"
