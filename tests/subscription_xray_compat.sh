#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$root/anticheburnet/files/usr/lib/subscription/parser.uc" > "$work/test.uc"
cat "$root/tests/subscription_xray_compat.uc" >> "$work/test.uc"
ucode -L "$root/anticheburnet/files/usr/lib" "$work/test.uc"
