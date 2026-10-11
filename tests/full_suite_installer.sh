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
mkdir -p "$WORK_DIR/fixtures" "$WORK_DIR/bin"
names=(
  forkop_1.0.1.apk
  luci-app-forkop_1.0.1.apk
  luci-i18n-forkop-ru_1.0.1.apk
  sing-box-extended_1.14.1-extended-2.7.2-forkop.1_openwrt_aarch64_cortex-a53.apk
  forkop-xray_26.10.10-r1_aarch64_cortex-a53.apk
  forkop-amneziawg_3.1.20260828-r2_aarch64_cortex-a53.apk
)
for name in "${names[@]}"; do
  printf 'fixture: %s\n' "$name" > "$WORK_DIR/fixtures/$name"
done
(cd "$WORK_DIR/fixtures" && sha256sum ./*.apk > SHA256SUMS)
cp "$WORK_DIR/fixtures/SHA256SUMS" "$WORK_DIR/good-sums"

cat > "$WORK_DIR/bin/apk" <<'SH'
#!/bin/sh
case "$1" in
  info)
    case " ${TEST_INSTALLED:-} " in *" $3 "*) exit 0 ;; esac
    [ "$3" = "${TEST_CONFLICT:-}" ]; exit $?
    ;;
  update) printf 'update\n' >> "$TEST_LOG" ;;
  del) printf 'del %s\n' "$2" >> "$TEST_LOG"; exit "${TEST_DELETE_STATUS:-0}" ;;
  add)
    printf 'apk %s\n' "$*" >> "$TEST_LOG"
    [ "$2" = --allow-untrusted ] && [ "$#" = 8 ] || exit 1
    shift 2
    for file do [ -s "$file" ] || exit 1; done
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$WORK_DIR/bin/apk"
export PATH="$WORK_DIR/bin:$PATH"
export TEST_LOG="$WORK_DIR/actions"
PKG_IS_APK=1

# Replace only router/network boundaries; retain argument parsing, release
# resolution, checksum validation, ordering and the six-file apk transaction.
check_root() { :; }
init_tmp_dir() { TMP_DIR="$WORK_DIR/downloads"; mkdir -p "$TMP_DIR"; }
detect_fetcher() { :; }
sync_time() { :; }
check_system() { check_full_suite_platform; }
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
      printf 'https://github.com/m-bezrukoff/forkop-plus/releases/download/1.0.1/%s\n' "$name"
      ;;
    installer-cleanup-legacy)
      printf 'cleanup\n' >> "$TEST_LOG"
      printf 'FORKOP_WAS_ENABLED=0\nFORKOP_WAS_RUNNING=0\nFORKOP_LEGACY_DETECTED=0\n'
      ;;
    installer-prepare-full-suite) printf 'prepare\n' >> "$TEST_LOG" ;;
    installer-post-install) printf 'post\n' >> "$TEST_LOG" ;;
    *) return 1 ;;
  esac
}
download_with_retry() { cp "$WORK_DIR/fixtures/$(basename "$1")" "$2"; }
# Used by migrate_legacy_configuration() from the sourced installer.
# shellcheck disable=SC2034
detect_legacy_installation() { FORKOP_LEGACY_DETECTED=0; }

run_installer() {
  : > "$TEST_LOG"
  (main "$@") > "$WORK_DIR/output" 2>&1
}
assert_no_replacement() {
  if grep -Eq '^(cleanup|prepare|apk|post)' "$TEST_LOG"; then
    fail "invalid suite changed packages or services"
  fi
}

run_installer < /dev/null || { cat "$WORK_DIR/output"; fail 'complete installation failed'; }
grep -Fq 'Forkop Plus 1.0.1:' "$WORK_DIR/output" || fail 'missing installation result'
[[ "$(grep -c '^apk add ' "$TEST_LOG")" = 1 ]] || fail 'suite must use one apk transaction'
for name in "${names[@]}"; do
  grep -Fq "$name" "$TEST_LOG" || fail "missing installed package: $name"
done
[[ "$(sed -n '3p' "$TEST_LOG")" = cleanup && "$(sed -n '4p' "$TEST_LOG")" = prepare &&
   "$(tail -n 1 "$TEST_LOG")" = post ]] || fail 'incorrect install ordering'
[[ ! -d "$WORK_DIR/downloads" ]] || fail 'temporary downloads were not removed'

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
export TEST_CONFLICT=xray-core
if run_installer; then fail 'xray-core conflict was accepted'; fi
assert_no_replacement
unset TEST_CONFLICT
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
  export FORKOP_INSTALLER_SING_BOX_INIT="$WORK_DIR/sing-box-init"
  export FORKOP_INSTALLER_DEADLINE_HELPER
  FORKOP_INSTALLER_DEADLINE_HELPER="$(install_deadline_helper_path)"
  export FORKOP_INSTALLER_COMMAND_RESULT="$WORK_DIR/command"
  export TEST_INSTALLED='sing-box sing-box-tiny'
  : > "$TEST_LOG"
  ucode "$helper" installer-prepare-full-suite || fail 'real component preparation failed'
  [[ "$(cat "$TEST_LOG")" = $'sing-box-stop\ndel sing-box\ndel sing-box-tiny' ]] || fail 'incorrect component preparation actions'
  : > "$TEST_LOG"
  export TEST_STOP_STATUS=1
  if ucode "$helper" installer-prepare-full-suite; then fail 'failed sing-box stop accepted'; fi
  [[ "$(cat "$TEST_LOG")" = sing-box-stop ]] || fail 'packages removed after stop failure'
  unset TEST_STOP_STATUS
  export TEST_DELETE_STATUS=1
  if ucode "$helper" installer-prepare-full-suite; then fail 'failed package removal accepted'; fi
else
  printf 'SKIP: embedded ucode checks (ucode unavailable)\n'
fi
printf 'full suite installer checks passed\n'
