#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if ! command -v ucode >/dev/null 2>&1; then
  printf 'SKIP: embedded ucode sing-box replacement checks (ucode unavailable)\n'
  exit 0
fi
awk '
  /cat > "\$helper_path" <<'\''EOF'\''/ { capture = 1; next }
  capture && /^let mode = ARGV/ { exit }
  capture { print }
' "$ROOT_DIR/install.sh" > "$WORK_DIR/helper.uc"
cat "$ROOT_DIR/tests/full_suite_components.uc" >> "$WORK_DIR/helper.uc"
ucode -c -o /dev/null "$WORK_DIR/helper.uc"
ucode -S -c -o /dev/null "$WORK_DIR/helper.uc"
FORKOP_TEST_DIR="$WORK_DIR" ucode "$WORK_DIR/helper.uc"
