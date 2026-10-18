#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^let mode = ARGV\[0\]/,$d' "$root/anticheburnet/files/usr/lib/service/state.uc" > "$work/check.uc"
cat "$root/tests/routing_reload_signatures.uc" >> "$work/check.uc"
ucode -L "$root/anticheburnet/files/usr/lib" "$work/check.uc"
