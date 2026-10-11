#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Exercise the real POSIX-shell entrypoint with router mutations replaced.
sed '/^main "\$@"$/d' "$ROOT_DIR/install.sh" > "$WORK_DIR/installer.sh"
cat >> "$WORK_DIR/installer.sh" <<'SH'
check_root() { printf 'root\n' >> "$TEST_LOG"; }
init_tmp_dir() { printf 'init\n' >> "$TEST_LOG"; }
detect_fetcher() { printf 'fetch\n' >> "$TEST_LOG"; }
sync_time() { printf 'time\n' >> "$TEST_LOG"; }
check_system() { printf 'system\n' >> "$TEST_LOG"; }
install_full_suite() { printf 'install\n' >> "$TEST_LOG"; }
uninstall_full_suite() { printf 'uninstall\n' >> "$TEST_LOG"; }
main "$@"
SH
export TEST_LOG="$WORK_DIR/actions"
run_installer() {
  local input="$1"
  shift
  : > "$TEST_LOG"
  printf '%b' "$input" | sh "$WORK_DIR/installer.sh" "$@" > "$WORK_DIR/output" 2>&1
}
assert_install() {
  [[ "$(cat "$TEST_LOG")" = $'root\ninit\nfetch\ntime\nsystem\ninstall' ]] ||
    fail 'installation ran in the wrong order'
}
assert_uninstall() {
  [[ "$(cat "$TEST_LOG")" = $'root\ninit\nuninstall' ]] ||
    fail 'uninstallation used installation or network operations'
}

for answer in '1\n' 'install\n'; do
  run_installer "$answer" || fail 'install selection failed'
  assert_install
  grep -Fq '1) install' "$WORK_DIR/output" || fail 'install option missing'
  grep -Fq '2) uninstall' "$WORK_DIR/output" || fail 'uninstall option missing'
done
for answer in '2\n' 'uninstall\n'; do
  run_installer "$answer" || fail 'uninstall selection failed'
  assert_uninstall
done
run_installer '\ninvalid\n2\n' || fail 'invalid input did not retry'
assert_uninstall
[[ "$(grep -c 'Enter 1 (install) or 2 (uninstall).' "$WORK_DIR/output")" = 2 ]] ||
  fail 'empty or invalid selection did not repeat the question'

for answer in '' '\n' 'invalid\n'; do
  if run_installer "$answer"; then fail 'missing selection started an action'; fi
  [[ "$(cat "$TEST_LOG")" = root ]] || fail 'EOF changed the router before selection'
done
run_installer '' --install || fail 'explicit install required input'
assert_install
if grep -Fq 'Select [1/2]' "$WORK_DIR/output"; then fail 'explicit install prompted'; fi
run_installer '' --uninstall || fail 'explicit uninstall required input'
assert_uninstall
if grep -Fq 'Select [1/2]' "$WORK_DIR/output"; then fail 'explicit uninstall prompted'; fi
for args in '--install --uninstall' '--uninstall --install' '--install --generic' \
            '--generic --install' '--generic --uninstall' '--uninstall --generic'; do
  # Intentional splitting of fixed argument combinations.
  # shellcheck disable=SC2086
  if run_installer '' $args; then fail 'conflicting modes accepted'; fi
  [[ ! -s "$TEST_LOG" ]] || fail 'conflicting modes started an action'
done
run_installer '' --help || fail 'help required input'
[[ ! -s "$TEST_LOG" ]] || fail 'help started an action'
grep -Fq -- '--install' "$WORK_DIR/output" || fail 'explicit install missing from help'
printf 'installer mode checks passed\n'
