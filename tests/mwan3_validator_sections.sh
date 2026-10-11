#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANTICHEBURNET_LIB="$ROOT_DIR/anticheburnet/files/usr/lib"
VALIDATOR="$ANTICHEBURNET_LIB/config/validator.uc"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat >"$WORK_DIR/enabled.state" <<'EOF'
mwan3.wan=interface
mwan3.wan.enabled=1
mwan3.backup=interface
mwan3.backup.enabled=0
EOF

ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/enabled.state" \
  ucode -L "$ANTICHEBURNET_LIB" "$VALIDATOR" mwan3-has-enabled-interface-from-sections ||
  fail "enabled mwan3 interface must be detected through core.uci"

cat >"$WORK_DIR/disabled.state" <<'EOF'
mwan3.wan=interface
mwan3.wan.enabled=0
EOF

if ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/disabled.state" \
  ucode -L "$ANTICHEBURNET_LIB" "$VALIDATOR" mwan3-has-enabled-interface-from-sections; then
  fail "disabled mwan3 interfaces must not be reported as active"
fi

printf 'mwan3 validator section checks passed\n'