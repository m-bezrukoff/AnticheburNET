#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANTICHEBURNET_BIN="$ROOT_DIR/anticheburnet/files/usr/bin/anticheburnet"
ANTICHEBURNET_LIB="$ROOT_DIR/anticheburnet/files/usr/lib"
PACKAGE_UC="$ANTICHEBURNET_LIB/service/package.uc"
ANTICHEBURNET_MAKEFILE="$ROOT_DIR/anticheburnet/Makefile"
LUCI_UCI_DEFAULTS="$ROOT_DIR/luci-app-anticheburnet/root/etc/uci-defaults/50_luci-anticheburnet"
BUILD_SCRIPT="$ROOT_DIR/build.sh"
WORK_DIR="$(mktemp -d)"
export ANTICHEBURNET_PACKAGE_UPGRADE_STATE="$WORK_DIR/package-was-running"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -r "$PACKAGE_UC" ] ||
  fail "service/package.uc must own package lifecycle logic"
if grep -n -E 'require\("uci"\)\.cursor|uci -q|uci", "-q"' "$PACKAGE_UC" >/dev/null 2>&1; then
  fail "service/package.uc must use core.uci instead of direct UCI cursor or CLI access"
fi
grep -Fq 'require("core.uci")' "$PACKAGE_UC" ||
  fail "service/package.uc must import core.uci"
grep -Fq 'package_prerm: [ "service/package.uc", "prerm", 1 ]' "$ANTICHEBURNET_BIN" ||
  fail "anticheburnet entrypoint must dispatch package prerm cleanup through service/package.uc"
grep -Fq 'package_postinst: [ "service/package.uc", "postinst", 0 ]' "$ANTICHEBURNET_BIN" ||
  fail "anticheburnet entrypoint must dispatch package postinst recovery through service/package.uc"
grep -Fq 'luci_postinst: [ "service/package.uc", "luci-postinst", 0 ]' "$ANTICHEBURNET_BIN" ||
  fail "anticheburnet entrypoint must dispatch LuCI postinstall cleanup through service/package.uc"
grep -Fq '#!/bin/sh' "$LUCI_UCI_DEFAULTS" ||
  fail "LuCI uci-defaults must remain a shell script because OpenWrt default_postinst runs it through shell"
grep -Fq '/usr/bin/anticheburnet luci_postinst' "$LUCI_UCI_DEFAULTS" ||
  fail "LuCI uci-defaults must delegate cache/rpcd handling to ucode"
if grep -E 'rm -f /var/luci-indexcache|rm -f /tmp/luci-indexcache|logger -t "anticheburnet"' "$LUCI_UCI_DEFAULTS" >/dev/null; then
  fail "LuCI uci-defaults must not own cache/logger shell logic"
fi

if grep -n -E 'grep -q "105 anticheburnet"|sed -i "/105 anticheburnet|anticheburnet_dont_touch_dhcp=.*uci|cp /etc/config/anticheburnet|rm -f /tmp/luci-indexcache|killall -HUP rpcd' "$ANTICHEBURNET_MAKEFILE" "$BUILD_SCRIPT" >/dev/null; then
  fail "package scripts must not keep backend/LuCI lifecycle business logic in shell"
fi
grep -Fq '#!/usr/bin/ucode' "$ANTICHEBURNET_MAKEFILE" ||
  fail "anticheburnet Makefile package hooks must use ucode entrypoints"
grep -Fq '/usr/bin/anticheburnet package_prerm' "$ANTICHEBURNET_MAKEFILE" ||
  fail "anticheburnet Makefile prerm must delegate cleanup to package_prerm"
grep -Fq '/usr/bin/anticheburnet package_postinst' "$ANTICHEBURNET_MAKEFILE" ||
  fail "anticheburnet Makefile postinst must restore a service that was running before upgrade"
grep -Fq '/usr/bin/anticheburnet package_prerm upgrade' "$BUILD_SCRIPT" ||
  fail "manual APK pre-upgrade must record and stop the running service"
grep -Fq '/usr/bin/anticheburnet package_postinst' "$BUILD_SCRIPT" ||
  fail "manual packages must restore a service that was running before upgrade"
if grep -Fq '/usr/bin/anticheburnet luci_postinst' "$BUILD_SCRIPT"; then
  fail "manual package hooks must let default_postinst run luci_postinst exactly once through uci-defaults"
fi
if grep -n -E 'Package/anticheburnet/preinst|copy_legacy_config|ANTICHEBURNET_LEGACY_CONFIG|mode == "preinst"' \
  "$ANTICHEBURNET_MAKEFILE" "$BUILD_SCRIPT" "$PACKAGE_UC" >/dev/null 2>&1; then
  fail "package hooks and runtime service must not own configuration migration"
fi

rt_tables="$WORK_DIR/rt_tables"
cat >"$rt_tables" <<'EOF'
100 main
105 anticheburnet
200 custom
EOF
ANTICHEBURNET_PACKAGE_TEST_MODE=1 ANTICHEBURNET_RT_TABLES="$rt_tables" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm
if grep -Fq '105 anticheburnet' "$rt_tables"; then
  fail "package prerm must remove the AnticheburNET routing table entry"
fi
grep -Fq '200 custom' "$rt_tables" ||
  fail "package prerm must preserve unrelated rt_tables entries"

cat >"$WORK_DIR/anticheburnet-init" <<'SH'
#!/usr/bin/env bash
grep -Fq '105 anticheburnet' "${ANTICHEBURNET_RT_TABLES:?}" || exit 1
printf '%s\n' 'stop-with-route-table' >>"${ANTICHEBURNET_STOP_LOG:?}"
SH
chmod 0755 "$WORK_DIR/anticheburnet-init"
cat >"$WORK_DIR/stop-order.state" <<'EOF_UCI'
anticheburnet.settings=settings
anticheburnet.settings.dont_touch_dhcp=1
EOF_UCI
printf '105 anticheburnet\n' >"$WORK_DIR/rt_tables_stop_order"
: >"$WORK_DIR/stop-order.log"
ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/stop-order.state" \
ANTICHEBURNET_INIT="$WORK_DIR/anticheburnet-init" \
ANTICHEBURNET_STOP_LOG="$WORK_DIR/stop-order.log" \
ANTICHEBURNET_BIN="$WORK_DIR/missing-anticheburnet-bin" \
ANTICHEBURNET_DNS_APPLY_UC="$WORK_DIR/missing-dns-apply.uc" \
ANTICHEBURNET_SING_BOX_INIT="$WORK_DIR/missing-sing-box-init" \
ANTICHEBURNET_SING_BOX_BIN="$WORK_DIR/missing-sing-box-bin" \
ANTICHEBURNET_SING_BOX_CRONET="$WORK_DIR/missing-cronet" \
ANTICHEBURNET_RT_TABLES="$WORK_DIR/rt_tables_stop_order" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm
grep -Fxq 'stop-with-route-table' "$WORK_DIR/stop-order.log" ||
  fail "package prerm must stop AnticheburNET before removing its routing table name"
[ ! -s "$WORK_DIR/rt_tables_stop_order" ] ||
  fail "package prerm must remove the routing table name after AnticheburNET stops"

touch "$WORK_DIR/luci-indexcache.one" "$WORK_DIR/luci-indexcache.two"
ANTICHEBURNET_PACKAGE_TEST_MODE=1 ANTICHEBURNET_LUCI_CACHE_GLOBS="$WORK_DIR/luci-indexcache*" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" luci-postinst
if compgen -G "$WORK_DIR/luci-indexcache*" >/dev/null; then
  fail "luci-postinst must remove LuCI index cache files"
fi

cat >"$WORK_DIR/anticheburnet-bin" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ANTICHEBURNET_RESTORE_LOG:?}"
SH
chmod 0755 "$WORK_DIR/anticheburnet-bin"

cat >"$WORK_DIR/dont-touch.state" <<'EOF_UCI'
anticheburnet.settings=settings
anticheburnet.settings.dont_touch_dhcp=1
EOF_UCI
printf '105 anticheburnet\n' >"$WORK_DIR/rt_tables_dont_touch"
: >"$WORK_DIR/restore-dont-touch.log"
ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/dont-touch.state" \
ANTICHEBURNET_RESTORE_LOG="$WORK_DIR/restore-dont-touch.log" \
ANTICHEBURNET_BIN="$WORK_DIR/anticheburnet-bin" \
ANTICHEBURNET_DNS_APPLY_UC="$WORK_DIR/missing-dns-apply.uc" \
ANTICHEBURNET_SING_BOX_INIT="$WORK_DIR/missing-sing-box-init" \
ANTICHEBURNET_SING_BOX_BIN="$WORK_DIR/missing-sing-box-bin" \
ANTICHEBURNET_SING_BOX_CRONET="$WORK_DIR/missing-cronet" \
ANTICHEBURNET_RT_TABLES="$WORK_DIR/rt_tables_dont_touch" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm
[ ! -s "$WORK_DIR/restore-dont-touch.log" ] ||
  fail "package prerm must skip dnsmasq restore when dont_touch_dhcp is enabled"

cat >"$WORK_DIR/restore.state" <<'EOF_UCI'
anticheburnet.settings=settings
anticheburnet.settings.dont_touch_dhcp=0
EOF_UCI
printf '105 anticheburnet\n' >"$WORK_DIR/rt_tables_restore"
: >"$WORK_DIR/restore.log"
ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/restore.state" \
ANTICHEBURNET_RESTORE_LOG="$WORK_DIR/restore.log" \
ANTICHEBURNET_BIN="$WORK_DIR/anticheburnet-bin" \
ANTICHEBURNET_DNS_APPLY_UC="$WORK_DIR/missing-dns-apply.uc" \
ANTICHEBURNET_SING_BOX_INIT="$WORK_DIR/missing-sing-box-init" \
ANTICHEBURNET_SING_BOX_BIN="$WORK_DIR/missing-sing-box-bin" \
ANTICHEBURNET_SING_BOX_CRONET="$WORK_DIR/missing-cronet" \
ANTICHEBURNET_RT_TABLES="$WORK_DIR/rt_tables_restore" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm
grep -Fxq 'restore_dnsmasq' "$WORK_DIR/restore.log" ||
  fail "package prerm must restore dnsmasq when dont_touch_dhcp is disabled"

cat >"$WORK_DIR/upgrade-init" <<'SH'
#!/usr/bin/env bash
case "$1" in
  status) exit "${ANTICHEBURNET_FAKE_STATUS:-0}" ;;
  start) printf '%s\n' start >>"${ANTICHEBURNET_START_LOG:?}" ;;
esac
SH
chmod 0755 "$WORK_DIR/upgrade-init"
: >"$WORK_DIR/upgrade-start.log"
: >"$WORK_DIR/rt_tables_upgrade"
ANTICHEBURNET_PACKAGE_TEST_MODE=1 \
ANTICHEBURNET_INIT="$WORK_DIR/upgrade-init" \
ANTICHEBURNET_START_LOG="$WORK_DIR/upgrade-start.log" \
ANTICHEBURNET_RT_TABLES="$WORK_DIR/rt_tables_upgrade" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm upgrade
[ -f "$ANTICHEBURNET_PACKAGE_UPGRADE_STATE" ] ||
  fail "package pre-upgrade must remember a running service"
cat >"$WORK_DIR/postinst-firewall.state" <<'EOF_UCI'
firewall.defaults=defaults
EOF_UCI
ANTICHEBURNET_PACKAGE_TEST_MODE=1 \
ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/postinst-firewall.state" \
ANTICHEBURNET_FIREWALL_INCLUDE_FILE="$WORK_DIR/anticheburnet-input.nft" \
ANTICHEBURNET_INIT="$WORK_DIR/upgrade-init" \
ANTICHEBURNET_START_LOG="$WORK_DIR/upgrade-start.log" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" postinst
grep -Fxq start "$WORK_DIR/upgrade-start.log" ||
  fail "package postinst must restart a service that was running before upgrade"
[ ! -e "$ANTICHEBURNET_PACKAGE_UPGRADE_STATE" ] ||
  fail "package postinst must clear the consumed upgrade state"

ANTICHEBURNET_PACKAGE_TEST_MODE=1 \
ANTICHEBURNET_FAKE_STATUS=1 \
ANTICHEBURNET_INIT="$WORK_DIR/upgrade-init" \
ANTICHEBURNET_RT_TABLES="$WORK_DIR/rt_tables_upgrade" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm upgrade
[ ! -e "$ANTICHEBURNET_PACKAGE_UPGRADE_STATE" ] ||
  fail "package pre-upgrade must not mark an already stopped service"

# Backend upgrade must preserve its separately managed sing-box runtime.
printf '#!/bin/sh\n# AnticheburNET managed sing-box service for binary variants\nexit 0\n' > "$WORK_DIR/managed-sing-box-init"
chmod 0755 "$WORK_DIR/managed-sing-box-init"
printf 'existing core\n' > "$WORK_DIR/managed-sing-box-bin"
printf 'existing cronet\n' > "$WORK_DIR/managed-cronet"
ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/stop-order.state" \
ANTICHEBURNET_INIT="$WORK_DIR/upgrade-init" \
ANTICHEBURNET_SING_BOX_INIT="$WORK_DIR/managed-sing-box-init" \
ANTICHEBURNET_SING_BOX_BIN="$WORK_DIR/managed-sing-box-bin" \
ANTICHEBURNET_SING_BOX_CRONET="$WORK_DIR/managed-cronet" \
ANTICHEBURNET_RT_TABLES="$WORK_DIR/rt_tables_upgrade" \
  ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" prerm upgrade
[ -s "$WORK_DIR/managed-sing-box-init" ] && [ -s "$WORK_DIR/managed-sing-box-bin" ] && \
  [ -s "$WORK_DIR/managed-cronet" ] || fail "backend upgrade removed the managed core"

# A self-update must not query the locked APK database from post-upgrade.
for defer_flag in ANTICHEBURNET_DEFER_PACKAGE_RESTART ANTICHEBURNET_UI_COMPONENT_ACTION_TRACKED; do
  printf '1\n' > "$ANTICHEBURNET_PACKAGE_UPGRADE_STATE"
  : > "$WORK_DIR/upgrade-start.log"
  env "$defer_flag=1" \
    ANTICHEBURNET_PACKAGE_TEST_MODE=1 \
    ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/postinst-firewall.state" \
    ANTICHEBURNET_FIREWALL_INCLUDE_FILE="$WORK_DIR/tproxy-input.nft" \
    ANTICHEBURNET_INIT="$WORK_DIR/upgrade-init" \
    ucode -L "$ANTICHEBURNET_LIB" "$PACKAGE_UC" postinst
  [ ! -s "$WORK_DIR/upgrade-start.log" ] || fail "self-update restarted inside the package transaction"
  [ ! -e "$ANTICHEBURNET_PACKAGE_UPGRADE_STATE" ] || fail "deferred restart left a stale upgrade marker"
done

printf 'package lifecycle checks passed\n'
