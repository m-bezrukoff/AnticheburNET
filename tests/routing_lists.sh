#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for pair in 'components/updates updates' 'service/state sources'; do
  read -r owner test <<<"$pair"
  sed '/^let mode = ARGV\[0\]/,$d' "$root/anticheburnet/files/usr/lib/$owner.uc" > "$work/check.uc"
  cat "$root/tests/routing_list_$test.uc" >> "$work/check.uc"
  ucode -L "$root/anticheburnet/files/usr/lib" "$work/check.uc"
done
