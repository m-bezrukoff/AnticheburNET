#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Exercise the hooks produced by the real packager without downloading SDKs
# or compiling ARM binaries. Only metadata and APK creation are stubbed.
awk '
  /^package_component\(\)/ { capture = 1 }
  capture { print }
  capture && /^}/ { exit }
' "$ROOT_DIR/components/build.sh" > "$WORK_DIR/packager.sh"
source "$WORK_DIR/packager.sh"
work="$WORK_DIR/components"
output="$WORK_DIR/output"
apk_bin="$WORK_DIR/apk"
SING_BOX_VERSION=test
mkdir -p "$output" "$WORK_DIR/init.d"
generate_apk_metadata_files() { :; }
unshare() { :; }
export TEST_COMPONENT_LOG="$WORK_DIR/actions"

for name in sing-box-extended anticheburnet-xray anticheburnet-amneziawg; do
  mkdir -p "$work/$name-root"
  package_component "$name" 1.0.0 'Test component' '' MIT
  service="$name"
  case "$name" in
    sing-box-extended) service=sing-box ;;
    anticheburnet-amneziawg) service=anticheburnet-awg ;;
  esac
  cat > "$WORK_DIR/init.d/$service" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> "$TEST_COMPONENT_LOG"
SH
  chmod +x "$WORK_DIR/init.d/$service"
  # Redirect the router's init.d boundary to a recording test service.
  sed "s|/etc/init.d/|$WORK_DIR/init.d/|g" "$work/$name-scripts/post.sh" > "$WORK_DIR/post.sh"

  for flag in ANTICHEBURNET_DEFER_PACKAGE_RESTART IPKG_NO_SCRIPT IPKG_INSTROOT; do
    : > "$TEST_COMPONENT_LOG"
    env ANTICHEBURNET_DEFER_PACKAGE_RESTART=0 IPKG_NO_SCRIPT=0 IPKG_INSTROOT= \
      "$flag=1" sh "$WORK_DIR/post.sh" || fail "$name hook failed with $flag"
    [[ ! -s "$TEST_COMPONENT_LOG" ]] || fail "$name enabled or restarted with $flag"
  done

  : > "$TEST_COMPONENT_LOG"
  ANTICHEBURNET_DEFER_PACKAGE_RESTART=0 IPKG_NO_SCRIPT=0 IPKG_INSTROOT= \
    sh "$WORK_DIR/post.sh"
  [[ "$(cat "$TEST_COMPONENT_LOG")" = $'enable\nrestart' ]] ||
    fail "$name standalone installation lost service setup"
done

printf 'component package lifecycle checks passed\n'
