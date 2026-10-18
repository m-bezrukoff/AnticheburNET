#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Exercise the actual package layout used by both APK and IPK self-updates.
awk '/^make_dir\(\)/{copy=1} /^build_app_root\(\)/{exit} copy{print}' "$ROOT_DIR/build.sh" > "$work/layout.sh"
source "$work/layout.sh"
RELEASE_VERSION=1.0.6
build_backend_root "$work/backend"
service="$work/backend/etc/init.d/anticheburnet-awg-subscriptions"
runner="$work/backend/usr/bin/anticheburnet-awg-subscription-run"
test -x "$service"
test -x "$runner"
test -f "$work/backend/usr/lib/anticheburnet/core/awg.uc"
test -f "$work/backend/usr/lib/anticheburnet/singbox/awg_recovery.uc"
test ! -d "$work/backend/usr/lib/anticheburnet-components"
grep -Fq 'procd_set_param command /usr/bin/anticheburnet-awg-subscription-run' "$service"
grep -Fq '/usr/lib/anticheburnet/core/awg.uc prepare' "$runner"
grep -Fq '/usr/lib/anticheburnet/core/awg.uc prepare-runtime' "$runner"
if grep -Fq 'anticheburnet-components' "$runner"; then
    echo 'Subscription runner must not require a component package upgrade' >&2
    exit 1
fi
bash -n "$runner" "$service"
printf 'AWG runtime is included in backend self-update packages\n'
