#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf '%s\n' '[{"tag":"priority","levels":[{"outbounds":["new-node"]},{"outbounds":["retained"]}]}]' > "$work/groups.json"
printf '%s\n' '{"priority":{"active":"retained","levelIndex":0,"activeDelay":42,"nextActiveCheck":0}}' > "$work/states.json"
ucode -L "$lib" "$lib/singbox/priority.uc" reconcile-groups-fixture "$work/groups.json" "$work/states.json" > "$work/retained.json"
node - "$work/retained.json" <<'JS'
const state = JSON.parse(require('fs').readFileSync(process.argv[2])).priority;
if (state.active !== 'retained' || state.levelIndex !== 1 || state.activeDelay !== 42) throw Error('valid active node must survive changed provider membership');
JS
printf '%s\n' '[{"tag":"priority","levels":[{"outbounds":["new-node"]}]}]' > "$work/groups.json"
ucode -L "$lib" "$lib/singbox/priority.uc" reconcile-groups-fixture "$work/groups.json" "$work/retained.json" > "$work/removed.json"
node - "$work/removed.json" <<'JS'
const state = JSON.parse(require('fs').readFileSync(process.argv[2])).priority;
if (state.active !== '' || state.levelIndex !== -1 || state.activeDelay !== 0) throw Error('removed node must be reselected from the new provider membership');
JS
printf 'Priority provider membership refresh checks passed\n'
