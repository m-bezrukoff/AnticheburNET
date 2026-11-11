#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ucode -L "$lib" "$root/tests/native_xray.uc"
awk '/^if \(sourcepath\(1\)/{exit} {print}' "$lib/singbox/xray.uc" > "$work/runtime.uc"
cat "$root/tests/native_xray_runtime.uc" >> "$work/runtime.uc"
ucode -L "$lib" "$work/runtime.uc"
sed -n '1,/^\/\/ INSERT_INSTALLER_FUNCTION/p' "$root/tests/installer_native_xray.uc" > "$work/installer.uc"
sed -n '/^function installer_xray_required()/,/^function installer_full_suite_plan(/p' "$root/install.sh" | sed '$d' >> "$work/installer.uc"
sed '1,/^\/\/ INSERT_INSTALLER_FUNCTION/d' "$root/tests/installer_native_xray.uc" >> "$work/installer.uc"
ucode "$work/installer.uc"
