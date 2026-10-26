#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed '/^let mode = ARGV\[0\]/,$d' "$root/anticheburnet/files/usr/lib/singbox/runtime.uc" > "$work/provider.uc"
cat "$root/tests/provider_ruleset_update.uc" >> "$work/provider.uc"
mkdir "$work/section-cache"
ANTICHEBURNET_SECTION_CACHE_DIR="$work/section-cache" \
  ucode -L "$root/anticheburnet/files/usr/lib" "$work/provider.uc" "$work"
