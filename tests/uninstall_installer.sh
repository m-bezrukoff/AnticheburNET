#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

sed '/^main "\$@"$/d' "$ROOT_DIR/install.sh" > "$WORK_DIR/installer.sh"
# shellcheck disable=SC1091
. "$WORK_DIR/installer.sh"
TEST_LOG="$WORK_DIR/actions"

check_root() { :; }
init_tmp_dir() { TMP_DIR="$WORK_DIR/temporary"; mkdir -p "$TMP_DIR"; }
check_uninstall_system() { [ "${TEST_SYSTEM_STATUS:-0}" -eq 0 ] || fail 'unsupported uninstall host'; }
detect_fetcher() { fail 'uninstallation requested a downloader'; }
sync_time() { fail 'uninstallation requested network time'; }
check_system() { fail 'uninstallation used install platform/space checks'; }
pkg_list_update() { fail 'uninstallation updated package feeds'; }
ensure_bootstrap_ucode_runtime() { fail 'uninstallation installed bootstrap packages'; }
backup_full_suite_configuration() {
  printf 'backup\n' >> "$TEST_LOG"
  [ "${TEST_BACKUP_STATUS:-0}" -eq 0 ] || fail 'backup failed'
  FULL_BACKUP_DIR="$WORK_DIR/backup"
}
install_json_ucode() {
  case "$1" in
    installer-uninstall-plan)
      printf 'plan\n' >> "$TEST_LOG"
      [ "${TEST_PLAN_STATUS:-0}" -eq 0 ] || return 1
      printf '%s\n' "${TEST_PLAN-anticheburnet luci-app-anticheburnet sing-box-extended anticheburnet-xray anticheburnet-amneziawg}"
      ;;
    installer-uninstall-suite)
      [[ "$ANTICHEBURNET_INSTALLER_REMOVE_PACKAGES" = "$FULL_REMOVE_PACKAGES" ]] || return 1
      printf 'uninstall\n' >> "$TEST_LOG"
      return "${TEST_UNINSTALL_STATUS:-0}"
      ;;
    *) fail "unexpected uninstall action: $1" ;;
  esac
}
run_uninstaller() {
  : > "$TEST_LOG"
  (main "$@") > "$WORK_DIR/output" 2>&1
}

run_uninstaller --uninstall || { cat "$WORK_DIR/output"; fail 'uninstallation failed'; }
[[ "$(cat "$TEST_LOG")" = $'plan\nbackup\nuninstall' ]] || fail 'incorrect uninstall ordering'
grep -Fq 'AnticheburNET uninstalled.' "$WORK_DIR/output" || fail 'missing completion message'
[[ ! -d "$WORK_DIR/temporary" ]] || fail 'temporary files not cleaned after success'

TEST_PLAN='' run_uninstaller --uninstall || fail 'repeated uninstall failed'
[[ "$(cat "$TEST_LOG")" = plan ]] || fail 'absent packages triggered backup or deletion'
grep -Fq 'already absent' "$WORK_DIR/output" || fail 'missing already-absent result'

if TEST_PLAN_STATUS=1 run_uninstaller --uninstall; then fail 'failed plan accepted'; fi
[[ "$(cat "$TEST_LOG")" = plan ]] || fail 'failed plan changed services or packages'
if TEST_BACKUP_STATUS=1 run_uninstaller --uninstall; then fail 'failed backup accepted'; fi
[[ "$(cat "$TEST_LOG")" = $'plan\nbackup' ]] || fail 'removal began after failed backup'
if TEST_UNINSTALL_STATUS=1 run_uninstaller --uninstall; then fail 'failed removal accepted'; fi
grep -Fq 'Uninstallation interrupted.' "$WORK_DIR/output" || fail 'missing recovery warning'
[[ -d "$WORK_DIR/temporary" ]] || fail 'temporary recovery files lost after failed removal'
if TEST_SYSTEM_STATUS=1 run_uninstaller --uninstall; then fail 'unsupported host accepted'; fi
[[ ! -s "$TEST_LOG" ]] || fail 'unsupported host started uninstall planning'

for args in '--generic --uninstall' '--uninstall --generic'; do
  # Intentional splitting of the two fixed argument combinations.
  # shellcheck disable=SC2086
  if run_uninstaller $args; then fail 'incompatible modes accepted'; fi
  [[ ! -s "$TEST_LOG" ]] || fail 'incompatible arguments started uninstallation'
done
run_uninstaller --help || fail 'installer help failed'
grep -Fq -- '--uninstall' "$WORK_DIR/output" || fail 'uninstall option missing from help'

if command -v ucode >/dev/null 2>&1; then
  # Execute the real ucode functions with only OS/package boundaries replaced.
  awk '
    /cat > "\$helper_path" <<'\''EOF'\''/ { capture = 1; next }
    capture && /^let mode = ARGV/ { exit }
    capture { print }
  ' "$ROOT_DIR/install.sh" > "$WORK_DIR/components.uc"
  cat "$ROOT_DIR/tests/uninstall_components.uc" >> "$WORK_DIR/components.uc"
  ucode "$WORK_DIR/components.uc" || fail 'embedded component uninstall checks failed'
else
  printf 'SKIP: native embedded ucode checks (ucode unavailable)\n'
fi

printf 'uninstall installer checks passed\n'
