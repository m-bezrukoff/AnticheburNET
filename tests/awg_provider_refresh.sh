#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ucode -L "$root/anticheburnet/files/usr/lib" "$root/tests/awg_provider_refresh.uc" "$work/input" "$work/output"
sed '/^let mode = ARGV\[0\]/,$d' "$root/anticheburnet/files/usr/lib/singbox/runtime.uc" > "$work/provider.uc"
cat "$root/tests/awg_provider_update.uc" >> "$work/provider.uc"
mkdir "$work/section-cache"
ANTICHEBURNET_SECTION_CACHE_DIR="$work/section-cache" \
  ucode -L "$root/anticheburnet/files/usr/lib" "$work/provider.uc" "$work"
