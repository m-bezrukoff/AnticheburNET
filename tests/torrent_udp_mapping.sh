#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$root/anticheburnet/files/usr/lib/singbox/generator.uc" > "$work/generator.uc"
cat "$root/tests/torrent_udp_mapping.uc" >> "$work/generator.uc"
ucode -L "$root/anticheburnet/files/usr/lib" "$work/generator.uc"
