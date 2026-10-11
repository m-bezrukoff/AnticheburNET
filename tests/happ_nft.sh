#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ANTICHEBURNET_LIB="${ANTICHEBURNET_TEST_LIB:-$ROOT_DIR/anticheburnet/files/usr/lib}"
NFT="${ANTICHEBURNET_TEST_NFT:-$ANTICHEBURNET_LIB/nft/apply.uc}"
STATE="${ANTICHEBURNET_TEST_STATE:-$ANTICHEBURNET_LIB/service/state.uc}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
export TMP_SUBSCRIPTION_FOLDER="$work"
export NFT_TEST_LOG="$work/nft.log"
cat > "$work/bin/nft" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$NFT_TEST_LOG"
SH
chmod +x "$work/bin/nft"
export PATH="$work/bin:$PATH"
cat > "$work/fixture.json" <<'JSON'
{"settings":{},"section":[{".name":"main","enabled":"1","action":"connection","subscription_urls":["https://example.com/sub"]}]}
JSON
check_rules() {
    : > "$NFT_TEST_LOG"
    ucode -L "$ANTICHEBURNET_LIB" "$NFT" nft-add-happ-real-ip-rules-fixture "$work/fixture.json" TestTable interfaces 0x04000000
}
check_rules
[ ! -s "$NFT_TEST_LOG" ]
cat > "$work/main-subscription-1.json" <<'JSON'
{"outbounds":[{"type":"vless","tag":"node"}],"happ_routing":{"enabled":true,"fake_dns":false}}
JSON
check_rules
[ "$(wc -l < "$NFT_TEST_LOG")" -eq 4 ]
grep -Fq 'mangle iifname @interfaces meta mark 0 meta l4proto tcp meta mark set 0x04000000 counter' "$NFT_TEST_LOG"
grep -Fq 'mangle iifname @interfaces meta mark 0 meta l4proto udp meta mark set 0x04000000 counter' "$NFT_TEST_LOG"
grep -Fq 'mangle_output meta mark 0 meta l4proto tcp meta mark set 0x04000000 counter' "$NFT_TEST_LOG"
grep -Fq 'mangle_output meta mark 0 meta l4proto udp meta mark set 0x04000000 counter' "$NFT_TEST_LOG"
active="$(ucode -L "$ANTICHEBURNET_LIB" "$NFT" nft-runtime-signature-fixture "$work/fixture.json")"
state_active="$(ucode -L "$ANTICHEBURNET_LIB" "$STATE" nft-signature-fixture "$work/fixture.json")"
cat > "$work/main-subscription-1.json" <<'JSON'
{"outbounds":[{"type":"vless","tag":"node"}],"happ_routing":{"enabled":false,"fake_dns":false}}
JSON
check_rules
[ ! -s "$NFT_TEST_LOG" ]
inactive="$(ucode -L "$ANTICHEBURNET_LIB" "$NFT" nft-runtime-signature-fixture "$work/fixture.json")"
[ "$active" != "$inactive" ]
state_inactive="$(ucode -L "$ANTICHEBURNET_LIB" "$STATE" nft-signature-fixture "$work/fixture.json")"
[ "$state_active" != "$state_inactive" ]
cat > "$work/main-subscription-1.json" <<'JSON'
{"outbounds":[{"type":"vless","tag":"node"}],"happ_routing":{"enabled":true,"fake_dns":true}}
JSON
check_rules
[ ! -s "$NFT_TEST_LOG" ]
cat > "$work/main-subscription-1.json" <<'JSON'
{"outbounds":[],"happ_routing":{"enabled":true,"fake_dns":false}}
JSON
check_rules
[ ! -s "$NFT_TEST_LOG" ]
cat > "$work/main-subscription-1.json" <<'JSON'
{"outbounds":[{"type":"vless","tag":"node"}],"happ_routing":{"enabled":true,"fake_dns":false}}
JSON
sed 's/"enabled":"1"/"enabled":"0"/' "$work/fixture.json" > "$work/disabled.json"
mv "$work/disabled.json" "$work/fixture.json"
check_rules
[ ! -s "$NFT_TEST_LOG" ]
printf 'Happ real IP nft regression checks passed\n'
