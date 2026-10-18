#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ucode -L "$ROOT_DIR/anticheburnet/files/usr/lib" "$ROOT_DIR/tests/fakeip_routing.uc" "$work/provider.json"
