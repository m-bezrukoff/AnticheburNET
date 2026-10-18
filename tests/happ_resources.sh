#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ucode -L "$root/anticheburnet/files/usr/lib" "$root/tests/happ_resources.uc" "$work"
