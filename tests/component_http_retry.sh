#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$root/anticheburnet/files/usr/lib/components/action.uc" >"$work/http.uc"
cat >>"$work/http.uc" <<'UC'
let calls = [], proxy_fails = false, all_fail = false, removed = 0;
function check(value, label) { if (!value) die(label + "\n"); }
command_exists = function(name) { return name == "curl"; };
command_success_from_args = function(args) {
    push(calls, args);
    let options = {};
    for (let i = 1; i < length(args) - 1; i++) options[args[i]] = args[i + 1];
    check(args[1] == "-q", "Ambient curl configuration must not change release requests");
    check(options["--retry"] == "2" && options["--retry-max-time"] == "10" &&
        index(args, "--retry-connrefused") >= 0, "Transient release reads must have bounded retries");
    check(options["--noproxy"] == "", "Ambient NO_PROXY must not bypass the selected connection");
    check(options["--proxy"] == "http://127.0.0.1:4534" || options["--proxy"] == "",
        "Fallback must explicitly disable ambient proxy settings");
    return !all_fail && !(proxy_fails && options["--proxy"] != "");
};
init_tmp_dir = function() {};
make_tmp_file = function(label) { return "/fixture/release.json"; };
read_file = function(path) { return "release metadata"; };
remove_file = function(path) { removed++; };
updates_log = function(message, level) {};
service_proxy_address = function() { return "127.0.0.1:4534"; };
check(http_get("https://example.test/release") == "release metadata" && length(calls) == 1,
    "A successful proxy request must not be repeated directly");
calls = []; proxy_fails = true;
check(http_get("https://example.test/release") == "release metadata" && length(calls) == 2 && removed == 3,
    "Failed proxy reads must clean partial output before a direct fallback");
calls = []; all_fail = true;
check(http_get("https://example.test/release") == "" && length(calls) == 2,
    "Exhausted reads must remain failures rather than use partial metadata");
calls = []; all_fail = false;
service_proxy_address = function() { return ""; };
check(http_get("https://example.test/release") == "release metadata" && length(calls) == 1,
    "Stopped service must allow one explicit direct request");
print("Component HTTP retry and transport isolation checks passed\n");
UC
ucode -L "$root/anticheburnet/files/usr/lib" "$work/http.uc"
