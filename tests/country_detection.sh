#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed '/^return {$/,$d' "$root/anticheburnet/files/usr/lib/singbox/country.uc" > "$work/country.uc"
cat "$root/tests/country_detection.uc" >> "$work/country.uc"
ucode -L "$root/anticheburnet/files/usr/lib" "$work/country.uc" "$work"
