#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${ANTICHEBURNET_TEST_LIB:-$ROOT_DIR/anticheburnet/files/usr/lib}"
NFT="${ANTICHEBURNET_TEST_NFT:-$LIB/nft/apply.uc}"
STATE="${ANTICHEBURNET_TEST_STATE:-$LIB/service/state.uc}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
export NFT_TEST_LOG="$work/nft.log"
cat > "$work/bin/nft" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$NFT_TEST_LOG"
SH
chmod +x "$work/bin/nft"
export PATH="$work/bin:$PATH"
previous_nft=''
previous_state=''
for strategy in selected happ tunnel; do
  printf '{"settings":{"routing_strategy":"%s"},"section":[{".name":"main","enabled":"1","action":"connection","selector_proxy_links":["socks5://example.com:1080"]}]}' "$strategy" > "$work/fixture"
  : > "$NFT_TEST_LOG"
  ucode -L "$LIB" "$NFT" nft-add-happ-real-ip-rules-fixture "$work/fixture" TestTable interfaces 0x04000000
  if [ "$strategy" = selected ]; then
    [ ! -s "$NFT_TEST_LOG" ]
  else
    [ "$(wc -l < "$NFT_TEST_LOG")" -eq 4 ]
    grep -Fq 'mangle iifname @interfaces meta mark 0 meta l4proto tcp meta mark set 0x04000000 counter' "$NFT_TEST_LOG"
    grep -Fq 'mangle_output meta mark 0 meta l4proto udp meta mark set 0x04000000 counter' "$NFT_TEST_LOG"
  fi
  nft="$(ucode -L "$LIB" "$NFT" nft-runtime-signature-fixture "$work/fixture")"
  state="$(ucode -L "$LIB" "$STATE" nft-signature-fixture "$work/fixture")"
  if [ -n "$previous_nft" ]; then
    [ "$nft" != "$previous_nft" ]
    [ "$state" != "$previous_state" ]
  fi
  previous_nft="$nft"
  previous_state="$state"
done
sed 's/"enabled":"1"/"enabled":"0"/' "$work/fixture" > "$work/disabled"
: > "$NFT_TEST_LOG"
ucode -L "$LIB" "$NFT" nft-add-happ-real-ip-rules-fixture "$work/disabled" TestTable interfaces 0x04000000
[ ! -s "$NFT_TEST_LOG" ]
printf 'Global routing strategy interception and signature checks passed\n'
