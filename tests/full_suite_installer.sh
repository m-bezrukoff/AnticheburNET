#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Load the real installer without invoking it on the test host.
sed '/^main "\$@"$/d' "$ROOT_DIR/install.sh" > "$WORK_DIR/installer.sh"
# shellcheck disable=SC1091
. "$WORK_DIR/installer.sh"
eval "$(declare -f check_system | sed '1s/check_system/real_check_system/; s|/etc/openwrt_release|"$WORK_DIR"/openwrt_release|g')"
eval "$(declare -f check_flash_space | sed '1s/check_flash_space/real_check_flash_space/')"
mkdir -p "$WORK_DIR/fixtures" "$WORK_DIR/bin"
names=(
  anticheburnet_1.0.1.apk
  luci-app-anticheburnet_1.0.1.apk
  luci-i18n-anticheburnet-ru_1.0.1.apk
  sing-box-extended_1.14.1-extended-2.7.2-anticheburnet.1_openwrt_aarch64_cortex-a53.apk
  anticheburnet-xray_26.10.10-r1_aarch64_cortex-a53.apk
  anticheburnet-amneziawg_3.1.20260828-r2_aarch64_cortex-a53.apk
)
for name in "${names[@]}"; do
  printf 'fixture: %s\n' "$name" > "$WORK_DIR/fixtures/$name"
done
(cd "$WORK_DIR/fixtures" && sha256sum ./*.apk > SHA256SUMS)
cp "$WORK_DIR/fixtures/SHA256SUMS" "$WORK_DIR/good-sums"

cat > "$WORK_DIR/bin/apk" <<'SH'
#!/bin/sh
preserve_env=0
if [ "$1" = --preserve-env ]; then
  preserve_env=1
  shift
fi
case "$1" in
  --version) printf 'apk-tools 3.0.0\n' ;;
  info)
    if [ "$#" -eq 1 ]; then printf '%s\n' $TEST_INSTALLED; exit 0; fi
    if [ "$2" = -r ]; then printf '%s\n' "${TEST_RDEPENDENCIES:-}"; exit 0; fi
    if [ -f "$TEST_REMOVED_FILE" ] && grep -Fxq "$3" "$TEST_REMOVED_FILE"; then exit 1; fi
    case " ${TEST_INSTALLED:-} " in *" $3 "*) exit 0 ;; esac
    [ "$3" = "${TEST_CONFLICT:-}" ]; exit $?
    ;;
  update) printf 'update\n' >> "$TEST_LOG" ;;
  del)
    shift
    if [ "$1" = --simulate ]; then exit "${TEST_SIMULATE_STATUS:-0}"; fi
    printf 'del %s\n' "$*" >> "$TEST_LOG"
    [ "${TEST_DELETE_STATUS:-0}" -eq 0 ] || exit "$TEST_DELETE_STATUS"
    printf '%s\n' "$@" >> "$TEST_REMOVED_FILE"
    ;;
  add)
    printf 'apk %s\n' "$*" >> "$TEST_LOG"
    if [ "$*" = 'add ucode ucode-mod-fs ucode-mod-uci' ]; then
      exit "${TEST_RUNTIME_STATUS:-0}"
    fi
    # APK 3 strips caller variables from hook environments unless requested.
    hook_defer=
    [ "$preserve_env" = 0 ] || hook_defer="${ANTICHEBURNET_DEFER_PACKAGE_RESTART:-}"
    env -i PATH="$PATH" ANTICHEBURNET_DEFER_PACKAGE_RESTART="$hook_defer" \
      sh -c '[ "$ANTICHEBURNET_DEFER_PACKAGE_RESTART" = 1 ]' || exit 1
    # Migration, firewall setup and LuCI post-install hooks must still execute.
    [ "${IPKG_NO_SCRIPT:-}" != 1 ] || exit 1
    [ "$2" = --allow-untrusted ] && [ "$#" = 8 ] || exit 1
    shift 2
    for file do [ -s "$file" ] || exit 1; done
    exit "${TEST_ADD_STATUS:-0}"
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$WORK_DIR/bin/apk"
export PATH="$WORK_DIR/bin:$PATH"
export TEST_LOG="$WORK_DIR/actions"
export TEST_REMOVED_FILE="$WORK_DIR/removed"
export ANTICHEBURNET_INSTALLER_SING_BOX_BIN="$WORK_DIR/sing-box-binary"
PKG_IS_APK=1

# Replace only router/network boundaries; retain argument parsing, release
# resolution, checksum validation, ordering and the six-file apk transaction.
check_root() { :; }
init_tmp_dir() { TMP_DIR="$WORK_DIR/downloads"; mkdir -p "$TMP_DIR"; }
detect_fetcher() { :; }
sync_time() { :; }
check_system() { check_full_suite_platform; }
check_flash_space() {
  printf 'flash\n' >> "$TEST_LOG"
  [ "${TEST_FLASH_STATUS:-0}" -eq 0 ] || fail 'not enough flash after replacement'
}
backup_full_suite_configuration() {
  printf 'backup\n' >> "$TEST_LOG"
  [ "${TEST_BACKUP_STATUS:-0}" -eq 0 ] || fail 'backup failed'
  FULL_BACKUP_DIR="$WORK_DIR/backup"
}
restore_full_suite_configuration() { printf 'restore\n' >> "$TEST_LOG"; }
ensure_bootstrap_ucode_runtime() { printf 'bootstrap\n' >> "$TEST_LOG"; }
read_openwrt_release_value() {
  case "$1" in
    DISTRIB_RELEASE) printf '%s\n' "${TEST_RELEASE:-25.12.3}" ;;
    DISTRIB_TARGET) printf '%s\n' "${TEST_TARGET:-mediatek/filogic}" ;;
    DISTRIB_ARCH) printf '%s\n' "${TEST_ARCH:-aarch64_cortex-a53}" ;;
  esac
}
fetch_github_latest_release_json() { printf '{}'; }
install_json_ucode() {
  # Match the real JSON helper's input consumption so pipefail sees no SIGPIPE.
  case "$1" in release-tag|release-asset-url) cat >/dev/null ;; esac
  case "$1" in
    release-tag) printf '1.0.1\n' ;;
    release-asset-url)
      [ "$2" != "${TEST_OMIT:-}" ] || return 0
      case "$2" in
        backend) name="${names[0]}" ;;
        app) name="${names[1]}" ;;
        i18n) name="${names[2]}" ;;
        sing-box) name="${names[3]}" ;;
        xray) name="${names[4]}" ;;
        awg) name="${names[5]}" ;;
        checksums) name=SHA256SUMS ;;
        *) return 1 ;;
      esac
      printf 'https://github.com/m-bezrukoff/AnticheburNET/releases/download/1.0.1/%s\n' "$name"
      ;;
    installer-cleanup-legacy)
      printf 'cleanup\n' >> "$TEST_LOG"
      printf 'ANTICHEBURNET_WAS_ENABLED=0\nANTICHEBURNET_WAS_RUNNING=0\nANTICHEBURNET_LEGACY_DETECTED=0\n'
      ;;
    installer-full-suite-plan)
      [ "${TEST_PLAN_STATUS:-0}" -eq 0 ] || return 1
      printf '%s\n' "${TEST_PLAN-sing-box}"
      ;;
    installer-prepare-full-suite)
      printf 'prepare\n' >> "$TEST_LOG"
      return "${TEST_PREPARE_STATUS:-0}"
      ;;
    installer-post-install)
      printf 'post\n' >> "$TEST_LOG"
      printf '%s\n' "$ANTICHEBURNET_INSTALLER_LANG" > "$WORK_DIR/language"
      ;;
    *) return 1 ;;
  esac
}
download_with_retry() { cp "$WORK_DIR/fixtures/$(basename "$1")" "$2"; }
# Used by migrate_legacy_configuration() from the sourced installer.
# shellcheck disable=SC2034
detect_legacy_installation() { ANTICHEBURNET_LEGACY_DETECTED=0; }

run_installer() {
  : > "$TEST_LOG"
  : > "$TEST_REMOVED_FILE"
  (main --install "$@") > "$WORK_DIR/output" 2>&1
}
assert_no_replacement() {
  if grep -Eq '^(cleanup|prepare|apk|post)' "$TEST_LOG"; then
    fail "invalid suite changed packages or services"
  fi
}

run_installer < /dev/null || { cat "$WORK_DIR/output"; fail 'complete installation failed'; }
grep -Fq 'AnticheburNET 1.0.1:' "$WORK_DIR/output" || fail 'missing installation result'
[[ "$(grep -c '^apk add --allow-untrusted ' "$TEST_LOG")" = 1 ]] || fail 'suite must use one apk transaction'
grep -Fxq 'apk add ucode ucode-mod-fs ucode-mod-uci' "$TEST_LOG" ||
  fail 'installer runtime must be retained with OpenWrt-compatible apk options'
for name in "${names[@]}"; do
  grep -Fq "$name" "$TEST_LOG" || fail "missing installed package: $name"
done
[[ "$(sed -n '3p' "$TEST_LOG")" = backup && "$(sed -n '5p' "$TEST_LOG")" = cleanup &&
   "$(sed -n '6p' "$TEST_LOG")" = prepare && "$(sed -n '7p' "$TEST_LOG")" = restore &&
   "$(sed -n '8p' "$TEST_LOG")" = flash &&
   "$(tail -n 1 "$TEST_LOG")" = post ]] || fail 'incorrect install ordering'
[[ ! -d "$WORK_DIR/downloads" ]] || fail 'temporary downloads were not removed'
[[ "$(cat "$WORK_DIR/language")" = en ]] || fail 'default English was not passed to post-install'
grep -Fq 'LuCI (en)' "$WORK_DIR/output" || fail 'result must report English'
run_installer <<< '2' || fail 'Russian installation failed'
[[ "$(cat "$WORK_DIR/language")" = ru ]] || fail 'Russian was not passed to post-install'
grep -Fq 'LuCI (ru)' "$WORK_DIR/output" || fail 'result must report Russian'

printf 'corrupted\n' >> "$WORK_DIR/fixtures/${names[4]}"
if run_installer; then fail 'corrupted Xray APK was accepted'; fi
assert_no_replacement
printf 'fixture: %s\n' "${names[4]}" > "$WORK_DIR/fixtures/${names[4]}"

head -n 5 "$WORK_DIR/good-sums" > "$WORK_DIR/fixtures/SHA256SUMS"
if run_installer; then fail 'incomplete checksum coverage was accepted'; fi
assert_no_replacement
cp "$WORK_DIR/good-sums" "$WORK_DIR/fixtures/SHA256SUMS"
cat "$WORK_DIR/good-sums" >> "$WORK_DIR/fixtures/SHA256SUMS"
if run_installer; then fail 'duplicate checksums were accepted'; fi
assert_no_replacement
sed '1s|\./|../|' "$WORK_DIR/good-sums" > "$WORK_DIR/fixtures/SHA256SUMS"
if run_installer; then fail 'checksum path traversal was accepted'; fi
assert_no_replacement
cp "$WORK_DIR/good-sums" "$WORK_DIR/fixtures/SHA256SUMS"

for kind in sing-box xray awg checksums backend app i18n; do
  TEST_OMIT="$kind"
  if run_installer; then fail "missing $kind asset was accepted"; fi
  assert_no_replacement
done
unset TEST_OMIT
TEST_TARGET=ramips/mt7621
if run_installer; then fail 'wrong target was accepted'; fi
assert_no_replacement
unset TEST_TARGET
TEST_ARCH=x86_64
if run_installer; then fail 'wrong architecture was accepted'; fi
assert_no_replacement
unset TEST_ARCH
TEST_RELEASE=24.10.4
if run_installer; then fail 'wrong OpenWrt version was accepted'; fi
assert_no_replacement
unset TEST_RELEASE
PKG_IS_APK=0
if run_installer; then fail 'opkg accepted for full suite'; fi
assert_no_replacement
# Used by package operations from the sourced installer.
# shellcheck disable=SC2034
PKG_IS_APK=1
export TEST_PLAN_STATUS=1
if run_installer; then fail 'failed replacement plan was accepted'; fi
assert_no_replacement
unset TEST_PLAN_STATUS
export TEST_PLAN=''
export TEST_FLASH_STATUS=1
if run_installer; then fail 'fresh install accepted insufficient flash'; fi
assert_no_replacement
if grep -Eq '^backup' "$TEST_LOG"; then fail 'fresh install backed up configuration without sufficient flash'; fi
unset TEST_PLAN TEST_FLASH_STATUS
# Orphaned/manual sing-box must bypass the fresh-install flash check and reach
# replacement before the authoritative post-removal check, even without APKs.
printf 'old binary\n' > "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN"
export TEST_PLAN=''
run_installer || { cat "$WORK_DIR/output"; fail 'orphaned sing-box blocked installation'; }
[[ "$(grep -c '^flash$' "$TEST_LOG")" = 1 ]] || fail 'orphaned binary checked flash before replacement'
[[ "$(sed -n '3p' "$TEST_LOG")" = backup && "$(sed -n '6p' "$TEST_LOG")" = prepare ]] ||
  fail 'orphaned binary skipped backed-up replacement'
export TEST_FLASH_STATUS=1
if run_installer; then fail 'orphan replacement accepted insufficient remaining flash'; fi
grep -Fxq prepare "$TEST_LOG" || fail 'orphaned binary prevented replacement at low flash'
if grep -Eq '^(apk add --allow-untrusted|post)' "$TEST_LOG"; then fail 'orphan replacement bypassed final flash check'; fi
rm "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN"
unset TEST_FLASH_STATUS
if ln -s "$WORK_DIR/missing-binary" "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN" 2>/dev/null &&
   [[ -L "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN" ]]; then
  run_installer || fail 'dangling sing-box symlink blocked replacement'
  [[ "$(grep -c '^flash$' "$TEST_LOG")" = 1 ]] || fail 'dangling symlink used fresh-install flash check'
else
  printf 'SKIP: dangling symlink fixture (unsupported on this host)\n'
fi
rm -f "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN"
unset TEST_PLAN
export TEST_BACKUP_STATUS=1
if run_installer; then fail 'failed configuration backup was accepted'; fi
assert_no_replacement
unset TEST_BACKUP_STATUS
export TEST_RUNTIME_STATUS=1
if run_installer; then fail 'failed runtime retention was accepted'; fi
if grep -Eq '^(cleanup|prepare|restore|apk add --allow-untrusted|post)' "$TEST_LOG"; then
  fail 'services or packages were replaced after runtime retention failure'
fi
unset TEST_RUNTIME_STATUS
export TEST_PREPARE_STATUS=1
if run_installer; then fail 'failed component removal was accepted'; fi
if grep -Eq '^(restore|flash|apk add --allow-untrusted|post)' "$TEST_LOG"; then
  fail 'installation continued after removal failure'
fi
[[ -d "$WORK_DIR/downloads" ]] || fail 'recovery packages lost after removal failure'
unset TEST_PREPARE_STATUS
export TEST_FLASH_STATUS=1
if run_installer; then fail 'insufficient flash after removal was accepted'; fi
if grep -Eq '^(apk add --allow-untrusted|post)' "$TEST_LOG"; then
  fail 'APK installation started without sufficient flash'
fi
[[ -d "$WORK_DIR/downloads" ]] || fail 'recovery packages lost after flash failure'
unset TEST_FLASH_STATUS
export TEST_ADD_STATUS=1
if run_installer; then fail 'failed APK transaction was accepted'; fi
if grep -Eq '^post' "$TEST_LOG"; then fail 'post-install ran after APK failure'; fi
[[ -d "$WORK_DIR/downloads" ]] || fail 'recovery packages lost after APK failure'
unset TEST_ADD_STATUS
run_installer || { cat "$WORK_DIR/output"; fail 'retry after interruption failed'; }

# The reported AX6000 layout must pass the initial platform/RAM check with
# 32 MiB free, then use actual df availability after freeing the old engine.
touch "$WORK_DIR/openwrt_release"
df() {
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  if [ "$2" = /tmp ]; then
    printf 'tmpfs 247868 1808 246060 1%% /tmp\n'
  else
    printf '/dev/ubi0_1 63420 27212 %s 45%% /overlay\n' "${TEST_AVAILABLE_KB:-32928}"
  fi
}
INSTALL_MODE=full
real_check_system || fail 'initial check rejected replaceable stock sing-box at 32 MiB'
if (real_check_flash_space) > "$WORK_DIR/flash-output" 2>&1; then
  fail 'post-removal flash check accepted only 32 MiB'
fi
TEST_AVAILABLE_KB=50000 real_check_flash_space || fail 'post-removal flash check rejected adequate space'
unset -f df
if run_installer --invalid; then fail 'unknown argument was accepted'; fi
assert_no_replacement
parse_args --generic
[[ "$INSTALL_MODE" = generic ]] || fail '--generic compatibility mode failed'

# Execute the documented command against a downloader which can return a
# partial script and fail. A failed fetch must never run that partial script.
cat > "$WORK_DIR/bin/wget" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in -O) TEST_SCRIPT="$2"; shift ;; esac
  shift
done
printf '%s\n' "$TEST_SCRIPT" > "$TEST_DOWNLOAD_PATH"
printf 'printf "downloaded-script-ran\\n" >> "$TEST_LOG"\n' > "$TEST_SCRIPT"
exit "${TEST_FETCH_STATUS:-0}"
SH
chmod +x "$WORK_DIR/bin/wget"
export TEST_DOWNLOAD_PATH="$WORK_DIR/download-path"
documented_command="$(awk '/^\( f=.*mktemp/ { print; exit }' "$ROOT_DIR/README.md")"
[[ -n "$documented_command" ]] || fail 'one-command installation missing from README'
: > "$TEST_LOG"
export TEST_FETCH_STATUS=1
if sh -c "$documented_command"; then fail 'documented command ignored failed download'; fi
[[ ! -s "$TEST_LOG" ]] || fail 'partial downloaded installer was executed'
[[ ! -e "$(cat "$TEST_DOWNLOAD_PATH")" ]] || fail 'failed download was not cleaned up'
unset TEST_FETCH_STATUS
sh -c "$documented_command" || fail 'documented command failed after successful download'
grep -Fxq downloaded-script-ran "$TEST_LOG" || fail 'downloaded installer was not executed'
[[ ! -e "$(cat "$TEST_DOWNLOAD_PATH")" ]] || fail 'downloaded installer was not cleaned up'

# In CI, also exercise the real embedded ucode asset matcher and reject
# ambiguous component assets. Local shell-only hosts still test the flow above.
if command -v ucode >/dev/null 2>&1; then
  TMP_DIR="$WORK_DIR/real-helper"
  mkdir -p "$TMP_DIR"
  helper="$(install_json_helper_path)"
  ucode -c -o /dev/null "$helper"
  ucode -S -c -o /dev/null "$helper"
  kinds=(backend app i18n sing-box xray awg)
  for i in "${!names[@]}"; do
    json="$(printf '{"tag_name":"1.0.1","assets":[{"name":"%s","browser_download_url":"expected"}]}' "${names[$i]}")"
    [[ "$(printf '%s' "$json" | ucode "$helper" release-asset-url "${kinds[$i]}" apk)" = expected ]] || fail "real ${kinds[$i]} matcher failed"
  done
  json="$(printf '{"tag_name":"1.0.1","assets":[{"name":"%s","browser_download_url":"first"},{"name":"%s","browser_download_url":"second"}]}' "${names[3]}" "${names[3]}")"
  [[ -z "$(printf '%s' "$json" | ucode "$helper" release-asset-url sing-box apk)" ]] || fail 'ambiguous asset accepted'

  cat > "$WORK_DIR/sing-box-init" <<'SH'
#!/bin/sh
printf 'sing-box-%s\n' "$1" >> "$TEST_LOG"
exit "${TEST_STOP_STATUS:-0}"
SH
  chmod +x "$WORK_DIR/sing-box-init"
  export ANTICHEBURNET_INSTALLER_SING_BOX_INIT="$WORK_DIR/sing-box-init"
  export ANTICHEBURNET_INSTALLER_DEADLINE_HELPER
  ANTICHEBURNET_INSTALLER_DEADLINE_HELPER="$(install_deadline_helper_path)"
  export ANTICHEBURNET_INSTALLER_COMMAND_RESULT="$WORK_DIR/command"
  export TEST_INSTALLED='sing-box sing-box-tiny'
  export ANTICHEBURNET_INSTALLER_REMOVE_PACKAGES='sing-box sing-box-tiny'
  : > "$TEST_LOG"
  : > "$TEST_REMOVED_FILE"
  printf 'old binary\n' > "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN"
  ucode "$helper" installer-prepare-full-suite || fail 'real component preparation failed'
  [[ "$(cat "$TEST_LOG")" = $'sing-box-stop\ndel sing-box sing-box-tiny' ]] || fail 'incorrect component preparation actions'
  [[ ! -e "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN" ]] || fail 'existing sing-box binary survived replacement'
  : > "$TEST_LOG"
  export TEST_STOP_STATUS=1
  printf 'old binary\n' > "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN"
  if ucode "$helper" installer-prepare-full-suite; then fail 'failed sing-box stop accepted'; fi
  [[ "$(cat "$TEST_LOG")" = sing-box-stop ]] || fail 'packages removed after stop failure'
  [[ -s "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN" ]] || fail 'binary removed after stop failure'
  unset TEST_STOP_STATUS
  export TEST_DELETE_STATUS=1
  : > "$TEST_REMOVED_FILE"
  if ucode "$helper" installer-prepare-full-suite; then fail 'failed package removal accepted'; fi
  [[ -s "$ANTICHEBURNET_INSTALLER_SING_BOX_BIN" ]] || fail 'binary removed after package removal failure'
  unset TEST_DELETE_STATUS
  export TEST_INSTALLED='sing-box sing-box-tiny anticheburnet unrelated-app'
  : > "$TEST_REMOVED_FILE"
  [[ "$(ucode "$helper" installer-full-suite-plan)" = $'sing-box\nsing-box-tiny\nanticheburnet' ]] ||
    fail 'replacement plan selected unrelated packages or missed managed packages'
  export TEST_RDEPENDENCIES='unrelated-app-1.0-r1'
  : > "$TEST_LOG"
  if ucode "$helper" installer-full-suite-plan; then fail 'shared engine was scheduled for removal'; fi
  [[ ! -s "$TEST_LOG" ]] || fail 'shared-dependency rejection stopped services or removed packages'
  unset TEST_RDEPENDENCIES
else
  printf 'SKIP: embedded ucode checks (ucode unavailable)\n'
fi
printf 'full suite installer checks passed\n'
