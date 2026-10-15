#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$lib/components/updates.uc" > "$work/check.uc"
cat "$root/tests/release_auto_update.uc" >> "$work/check.uc"
ucode -L "$lib" "$work/check.uc"
