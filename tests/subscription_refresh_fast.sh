#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/runtime" "$work/persistent"
sed '/^let mode = ARGV\[0\]/,$d' "$lib/subscription/cache.uc" > "$work/fast.uc"
cat >> "$work/fast.uc" <<'UC'
let body = "socks5://user:fixture@127.0.0.1:8080#fixture\n";
let headers = "HTTP/1.1 200 OK\r\nSubscription-Userinfo: upload=1; download=2; total=100\r\n";
let downloads = 0, normalizations = 0, current = true;
let parser = require("subscription.parser");
let normalize = parser.normalize_content_validated;
system = function(command) { die("Unexpected external command during subscription parsing\n"); };
fs.popen = function(command) { die("Plain subscription bodies must not launch gzip or a shell\n"); };
parser.normalize_content_validated = function(input, output) {
    normalizations++;
    return normalize(input, output);
};
subscription_parser = function() { return parser; };
log_message = function(message, level) {};
get_subscription_user_agent = function(value) { return value || "Happ"; };
get_subscription_hwid = function(value) { return value || "fixture-device"; };
subscription_config_is_current = function() { return current; };
download_subscription = function(url, output, proxy, header_output) {
    downloads++;
    write_text(output, body);
    write_text(header_output, headers);
    return 0;
};
let dir = getenv("TMP_SUBSCRIPTION_FOLDER");
let normalized = dir + "/proxy-subscription-1.json";
let metadata = dir + "/metadata.json";
function refresh(agent, url) {
    return download_subscription_into_cache("proxy", url || "https://fixture.test", normalized,
        dir + "/proxy-subscription-1.url", "", agent || "", "fixture-device", 1,
        "proxy-subscription-1", metadata, [], {}, 2000);
}
if (refresh() != 0 || normalizations != 1) die("Initial response must be normalized\n");
let first = read_text(normalized);
headers = replace(headers, "download=2", "download=3");
if (refresh() != 2 || downloads != 2 || normalizations != 1 || read_text(normalized) != first)
    die("Unchanged response must still download but reuse validated nodes\n");
if (read_json(metadata).traffic.used != 4)
    die("Fresh response metadata must not be cached with the nodes\n");
if (refresh("Mihomo") != 2 || normalizations != 2)
    die("Request profile changes must invalidate response reuse\n");
if (refresh("Mihomo", "https://other.test") != 2 || normalizations != 3)
    die("Source URL changes must invalidate response reuse\n");
headers += "Routing-Enable: false\r\n";
if (refresh() != 0 || normalizations != 4)
    die("Happ routing header changes must invalidate response reuse\n");
headers = "HTTP/1.1 301 Moved\r\nRouting-Enable: true\r\n" + headers;
if (refresh() != 2 || normalizations != 4)
    die("Only the final response routing headers should invalidate reuse\n");
write_text(normalized, replace(read_text(normalized), "8080", "8081"));
if (refresh() != 0 || normalizations != 5)
    die("Modified normalized cache must not inherit response validation\n");
body = replace(body, "8080", "8082");
if (refresh() != 0 || normalizations != 6 || index(read_text(normalized), "8082") < 0)
    die("Changed nodes must be normalized and committed\n");
current = false;
if (refresh() != 4 || normalizations != 6)
    die("Unchanged response must still check for superseded source settings\n");
current = true;
let response_path = source_response_path("proxy-subscription-1");
if (cache_name_from_file(response_path) != "proxy-subscription-1")
    die("Response cache must follow source cache pruning\n");
if ((fs.stat(response_path).mode & 0777) != 0600)
    die("Response cache credentials must be private\n");
remove_subscription_source_runtime_cache("proxy-subscription-1");
if (fs.stat(response_path) != null) die("Removing a source must remove its response cache\n");
if (user_agent_candidates("", "Mihomo", "Happ")[0] != "Mihomo")
    die("A proven request profile must precede compatibility attempts\n");
print("fast subscription refresh and cache invalidation checks passed\n");
UC
ANTICHEBURNET_LIB="$lib" TMP_SUBSCRIPTION_FOLDER="$work/runtime" ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_DIR="$work/persistent" \
  ucode -L "$lib" "$work/fast.uc"
