#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
lib="$ROOT_DIR/anticheburnet/files/usr/lib"
for fixture in plan update; do
  module=updater
  [[ "$fixture" != update ]] || module=action
  awk '/^let mode = ARGV\[0\]/{exit} {print}' "$lib/components/$module.uc" > "$WORK_DIR/$fixture.uc"
  cat "$ROOT_DIR/tests/anticheburnet_suite_$fixture.uc" >> "$WORK_DIR/$fixture.uc"
  ANTICHEBURNET_VERSION=1.2.3 ucode -L "$lib" "$WORK_DIR/$fixture.uc"
done
