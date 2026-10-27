#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^let mode = ARGV\[0\]/,$d' "$root/anticheburnet/files/usr/lib/subscription/cache.uc" > "$work/check.uc"
cat "$root/tests/subscription_download_retry.uc" >> "$work/check.uc"
ANTICHEBURNET_LIB="$root/anticheburnet/files/usr/lib" ucode -L "$root/anticheburnet/files/usr/lib" "$work/check.uc"
