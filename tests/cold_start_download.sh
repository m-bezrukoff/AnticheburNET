#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
LIB="$ROOT_DIR/anticheburnet/files/usr/lib"
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$LIB/service/lifecycle.uc" >"$WORK_DIR/start.uc"
cat >>"$WORK_DIR/start.uc" <<'UC'
let intercepted = false, generated = false, populated = false;
validate_start_config = function() { return 0; };
external_config_fingerprint = function() { return "fixture"; };
module_status = function(module, args) { return 0; };
module_success = function(module, args) { return true; };
module_background = function(module, args) {};
log_message = function(message, level) {};
acquire_start_subscription_update_lock = function() { return true; };
release_start_subscription_update_lock = function() {};
prepare_subscription_caches = function(mode) { return 0; };
singbox_init_config = function() {
    if (intercepted) die("Cold-start download intercepted before proxy start\n");
    if (nft_populate_enabled != 0) die("Generation tried to populate absent nft table\n");
    generated = true;
    return 0;
};
nft_rebuild_runtime = function() {
    if (!generated) die("Interception enabled before configuration generation\n");
    intercepted = true;
    return 0;
};
nft_populate_runtime_sets = function() {
    if (!intercepted || !generated) die("Runtime sets populated before preparation\n");
    populated = true;
    return 0;
};
refresh_cron = function() { return 0; };
command_success_from_args = function(args) {
    if (!populated) die("Proxy started before nft runtime sets were ready\n");
    return true;
};
if (start_main() != 0 || !generated || !intercepted || !populated) die("Cold start failed\n");
// A generation error must not enable traffic interception.
intercepted = false;
singbox_init_config = function() { return 7; };
if (start_main() != 7 || intercepted) die("Failed generation enabled interception\n");
UC
ucode -L "$LIB" "$WORK_DIR/start.uc"
printf 'Cold-start download and interception ordering checks passed\n'
