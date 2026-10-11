#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ANTICHEBURNET_LIB="${ANTICHEBURNET_TEST_LIB:-$ROOT_DIR/anticheburnet/files/usr/lib}"
STATUS="${ANTICHEBURNET_TEST_STATUS:-$ANTICHEBURNET_LIB/diagnostics/status.uc}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/config.json" <<'JSON'
{"route":{"final":"direct-out","rules":[
 {"action":"resolve","domain":"ip.podkop.fyi","server":"dns-server"},
 {"action":"route-options","domain":"ip.podkop.fyi"},
 {"action":"route","domain":"ip.podkop.fyi","outbound":"main-out"}
]}}
JSON
result="$(ucode -L "$ANTICHEBURNET_LIB" "$STATUS" check-proxy-outbound-tag "$work/config.json" ip.podkop.fyi)"
[ "$result" = main-out ] || { printf 'Expected VPN route, got %s\n' "$result" >&2; exit 1; }
cat > "$work/config.json" <<'JSON'
{"route":{"rules":[{"domain":["other.example","ip.podkop.fyi"],"outbound":"legacy-out"}]}}
JSON
[ "$(ucode -L "$ANTICHEBURNET_LIB" "$STATUS" check-proxy-outbound-tag "$work/config.json" ip.podkop.fyi)" = legacy-out ]
cat > "$work/config.json" <<'JSON'
{"outbounds":[{"type":"selector","tag":"main-out","outbounds":["nl","fi"],"default":"nl"}],"inbounds":[{"type":"tproxy"}],"experimental":{"clash_api":{},"cache_file":{"path":"live.db"}}}
JSON
printf '%s' '{"proxies":{"main-out":{"now":"fi"}}}' | ucode -L "$ANTICHEBURNET_LIB" "$STATUS" prepare-check-proxy-config "$work/config.json" "$work/check.json" "$work/cache.db"
ucode -e 'let c=json(require("fs").readfile(ARGV[0])); if(c.outbounds[0].default!="fi" || length(c.inbounds)!=0 || c.experimental.clash_api!=null || c.experimental.cache_file.path!=ARGV[1]) exit(1);' "$work/check.json" "$work/cache.db"
printf '%s' '{"proxies":{"main-out":{"now":"unknown"}}}' | ucode -L "$ANTICHEBURNET_LIB" "$STATUS" prepare-check-proxy-config "$work/config.json" "$work/check.json" "$work/cache.db"
ucode -e 'if(json(require("fs").readfile(ARGV[0])).outbounds[0].default!="nl") exit(1);' "$work/check.json"
printf 'Proxy IP route regression checks passed\n'
