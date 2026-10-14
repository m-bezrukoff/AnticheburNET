#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed '/^let mode = ARGV\[0\]/,$d' "$lib/subscription/cache.uc" > "$work/budget.uc"
cat >> "$work/budget.uc" <<'UC'
let elapsed_ms = 0, attempts = [];
monotonic_milliseconds = function() { return elapsed_ms; };
ensure_dir = function(path) { return true; };
unlink_path = function(path) {};
log_message = function(message, level) {};
system = function(command) { die("Unexpected shell command or retry sleep\n"); };
get_subscription_user_agent = function(value) { return value || "Happ"; };
user_agent_candidates = function(configured, preferred, fallback) { return [ "Happ", "Mihomo", "v2rayN" ]; };
subscription_parser = function() { return {
    try_decode_gzip_content_file: function(path) { return false; },
    extract_ui_metadata_file: function(headers, raw, output) { return false; },
    normalize_content_validated: function(raw, output) { return false; }
}; };
download_subscription = function(url, path, proxy, headers, agent, hwid, device, budget) {
    push(attempts, budget);
    if (budget < 1500) { elapsed_ms += budget; return 28; }
    elapsed_ms += 1500;
    return 0;
};
let status = download_subscription_into_cache("proxy", "https://example.test", "/tmp/cache.json", "/tmp/cache.url", "", "", "fixture", 1, "proxy-subscription-1", "", [], {}, 2000);
if (status != 1 || elapsed_ms != 2000 || length(attempts) != 2 || attempts[0] != 2000 || attempts[1] != 500)
    die("Compatibility profiles exceeded the shared request budget\n");
print("subscription request budget checks passed\n");
UC
ANTICHEBURNET_LIB="$lib" ucode -L "$lib" "$work/budget.uc"
