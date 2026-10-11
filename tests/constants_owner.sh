#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANTICHEBURNET_BIN="$ROOT_DIR/anticheburnet/files/usr/bin/anticheburnet"
ANTICHEBURNET_LIB="$ROOT_DIR/anticheburnet/files/usr/lib"
CLI_UC="$ANTICHEBURNET_BIN"
ANTICHEBURNET_MAKEFILE="$ROOT_DIR/anticheburnet/Makefile"
BUILD_SCRIPT="$ROOT_DIR/build.sh"
CONSTANTS_SH="$ANTICHEBURNET_LIB/constants.sh"
LIFECYCLE_UC="$ANTICHEBURNET_LIB/service/lifecycle.uc"
CONSTANTS_UC="$ANTICHEBURNET_LIB/core/constants.uc"
SINGBOX_CONSTANTS_UC="$ANTICHEBURNET_LIB/singbox/constants.uc"
FRONTEND_CONSTANTS="$ROOT_DIR/fe-app-anticheburnet/src/constants.ts"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ ! -e "$CONSTANTS_SH" ] ||
  fail "constants.sh shell owner must be removed"

grep -Fq '#!/usr/bin/ucode' "$ANTICHEBURNET_BIN" ||
  fail "anticheburnet entrypoint must be a direct ucode executable"
grep -Fq 'service/lifecycle.uc' "$CLI_UC" ||
  fail "service/cli.uc must dispatch lifecycle orchestration through service/lifecycle.uc"
grep -Fq 'core.constants' "$LIFECYCLE_UC" ||
  fail "service/lifecycle.uc must load constants from core/constants.uc"

if grep -R -n -E 'constants\.sh|read_shell_constants|expand_shell_constants|unquote_shell_value' \
  "$ANTICHEBURNET_BIN" "$ANTICHEBURNET_LIB" --include='*.sh' --include='*.uc' >/dev/null 2>&1; then
  fail "shell constants owner or parser references must not remain"
fi

if grep -n 'constants\.sh' "$ANTICHEBURNET_MAKEFILE" "$BUILD_SCRIPT" >/dev/null 2>&1; then
  fail "package build must not patch removed constants.sh"
fi
grep -Fq 'core/constants.uc' "$ANTICHEBURNET_MAKEFILE" ||
  fail "anticheburnet/Makefile must patch core/constants.uc"
grep -Fq 'core/constants.uc' "$BUILD_SCRIPT" ||
  fail "release build must patch core/constants.uc"

config_name="$(ucode -L "$ANTICHEBURNET_LIB" "$CONSTANTS_UC" get ANTICHEBURNET_CONFIG_NAME)"
[ "$config_name" = "anticheburnet" ] ||
  fail "core/constants.uc get returned unexpected ANTICHEBURNET_CONFIG_NAME"

eval "$(ucode -L "$ANTICHEBURNET_LIB" "$CONSTANTS_UC" shell-env)"
[ "$ANTICHEBURNET_CONFIG" = "/etc/config/anticheburnet" ] ||
  fail "core/constants.uc shell-env did not derive ANTICHEBURNET_CONFIG"
[ "$TMP_RULESET_FOLDER" = "/tmp/sing-box/rulesets" ] ||
  fail "core/constants.uc shell-env did not derive TMP_RULESET_FOLDER"
[ "$BYEDPI_PID_DIR" = "/var/run/anticheburnet/byedpi/pid" ] ||
  fail "core/constants.uc shell-env did not derive BYEDPI_PID_DIR"

[ "$(ucode -L "$ANTICHEBURNET_LIB" "$CONSTANTS_UC" get FAKEIP_TEST_DOMAIN)" = "fakeip.podkop.fyi" ] ||
  fail "FakeIP diagnostics must use the deployed public endpoint"
[ "$(ucode -L "$ANTICHEBURNET_LIB" "$CONSTANTS_UC" get CHECK_PROXY_IP_DOMAIN)" = "ip.podkop.fyi" ] ||
  fail "public IP diagnostics must use the deployed public endpoint"
grep -Fq 'const FAKEIP_TEST_DOMAIN = "fakeip.podkop.fyi";' "$SINGBOX_CONSTANTS_UC" ||
  fail "sing-box constants must match the deployed FakeIP endpoint"
grep -Fq "export const FAKEIP_CHECK_DOMAIN = 'fakeip.podkop.fyi';" "$FRONTEND_CONSTANTS" ||
  fail "LuCI diagnostics must use the deployed FakeIP endpoint"
grep -Fq "export const IP_CHECK_DOMAIN = 'ip.podkop.fyi';" "$FRONTEND_CONSTANTS" ||
  fail "LuCI diagnostics must use the deployed public IP endpoint"

printf 'constants ownership checks passed\n'
