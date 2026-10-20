#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
lib="$ROOT_DIR/anticheburnet/files/usr/lib"
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$lib/components/action.uc" > "$WORK_DIR/test.uc"
cat "$ROOT_DIR/tests/component_selection.uc" >> "$WORK_DIR/test.uc"
ucode -L "$lib" "$WORK_DIR/test.uc"
