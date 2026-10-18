#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^let mode = ARGV\[0\]/,$d' "$root/anticheburnet/files/usr/lib/components/updates.uc" > "$work/check.uc"
cat "$root/tests/subscription_auto_update.uc" >> "$work/check.uc"
ucode -L "$root/anticheburnet/files/usr/lib" "$work/check.uc"
