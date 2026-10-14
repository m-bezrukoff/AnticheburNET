#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATES_UC="$ROOT_DIR/anticheburnet/files/usr/lib/components/updates.uc"
REAL_LIB="$ROOT_DIR/anticheburnet/files/usr/lib"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

write_stub() {
  local path="$1"
  local body="$2"

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$body" >"$path"
}

stub_header='#!/usr/bin/env ucode
let fs = require("fs");

function as_string(value) {
    return value == null ? "" : "" + value;
}

function shell_quote(value) {
    return "'"'"'" + replace(as_string(value), /'"'"'/g, "'"'"'\\'"'"''"'"'") + "'"'"'";
}

function record(line) {
    let path = getenv("FAKE_CALL_LOG") || "";
    if (path != "")
        system("printf '"'"'%s\\n'"'"' " + shell_quote(line) + " >> " + shell_quote(path));
}
'

FAKE_LIB="$WORK_DIR/lib"

write_stub "$FAKE_LIB/subscription/cache.uc" "$stub_header"'
let mode = as_string(ARGV[0]);
record("subscription/cache:" + mode);
if (mode == "ensure-runtime-dirs")
    exit(0);
if (mode == "update-request") {
    print(getenv("FAKE_SUBSCRIPTION_UPDATE_SUMMARY") || "1 0 0 0", "\n");
    exit(0);
}
exit(64);
'

write_stub "$FAKE_LIB/service/state.uc" "$stub_header"'
let mode = as_string(ARGV[0]);
record("service/state:" + mode);
if (mode == "sing-box-service-runtime-pid") {
    print("3285\n");
    exit(0);
}
if (mode == "acquire-runtime-dir-lock" ||
    mode == "acquire-runtime-dir-lock-wait" ||
    mode == "release-runtime-dir-lock" ||
    mode == "reload-sing-box-runtime" ||
    mode == "write-current-reload-state-clean" ||
    mode == "run-pending-reload-if-requested")
    exit(0);
exit(64);
'

write_stub "$FAKE_LIB/server/service.uc" "$stub_header"'
record("server/service:" + as_string(ARGV[0]));
exit(ARGV[0] == "prepare-all-defaults" ? 0 : 64);
'

write_stub "$FAKE_LIB/config/validator.uc" "$stub_header"'
record("config/validator:" + as_string(ARGV[0]));
exit(ARGV[0] == "validate-runtime" ? 0 : 64);
'

write_stub "$FAKE_LIB/singbox/runtime.uc" "$stub_header"'
let mode = as_string(ARGV[0]);
record("singbox/runtime:" + mode + ":" + as_string(ARGV[1]));
if (mode == "update-providers")
    exit(int(getenv("FAKE_PROVIDER_FAIL") || "0"));
exit(64);
'

write_stub "$FAKE_LIB/singbox/priority.uc" "$stub_header"'
let mode = as_string(ARGV[0]);
record("singbox/priority:" + mode);
if (mode == "stop-runtime" || mode == "start-runtime")
    exit(0);
exit(64);
'

write_stub "$FAKE_LIB/singbox/dns_failover.uc" "$stub_header"'
let mode = as_string(ARGV[0]);
record("singbox/dns_failover:" + mode);
if (mode == "stop-runtime" || mode == "start-runtime")
    exit(0);
exit(64);
'

run_update() {
  local summary="$1"
  local log="$2"

  : >"$log"
  env \
    ANTICHEBURNET_LIB="$FAKE_LIB" \
    ANTICHEBURNET_RUNTIME_STATE_DIR="$WORK_DIR/run" \
    ANTICHEBURNET_SUBSCRIPTION_UPDATE_LOCK_DIR="$WORK_DIR/run/subscription-update.lock" \
    ANTICHEBURNET_RELOAD_LOCK_DIR="$WORK_DIR/run/reload.lock" \
    ANTICHEBURNET_SUBSCRIPTION_UPDATE_STATE_DIR="$WORK_DIR/run/subscription-update" \
    ANTICHEBURNET_SUBSCRIPTION_UPDATE_JOB_DIR="$WORK_DIR/run/subscription-update-jobs" \
    ANTICHEBURNET_SUBSCRIPTION_LINKS_DIR="$WORK_DIR/run/subscription-links" \
    ANTICHEBURNET_SUBSCRIPTION_METADATA_DIR="$WORK_DIR/run/subscription-metadata" \
    ANTICHEBURNET_OUTBOUND_METADATA_DIR="$WORK_DIR/run/outbound-metadata" \
    ANTICHEBURNET_SECTION_CACHE_DIR="$WORK_DIR/run/section-cache" \
    ANTICHEBURNET_RUNTIME_CACHE_FORMAT_FILE="$WORK_DIR/run/cache-format" \
    ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_DIR="$WORK_DIR/persistent/subscription-cache" \
    ANTICHEBURNET_PERSISTENT_SUBSCRIPTION_CACHE_FORMAT_FILE="$WORK_DIR/persistent/subscription-cache/cache-format" \
    ANTICHEBURNET_PENDING_RELOAD_FILE="$WORK_DIR/run/reload.pending" \
    ANTICHEBURNET_RELOAD_STATE_FILE="$WORK_DIR/run/reload-state" \
    ANTICHEBURNET_RULE_CONDITION_CACHE_DIR="$WORK_DIR/run/rule-condition-cache" \
    FAKE_CALL_LOG="$log" \
    FAKE_SUBSCRIPTION_UPDATE_SUMMARY="$summary" \
    ucode -L "$REAL_LIB" "$UPDATES_UC" subscription-update-if-due
}

updated_log="$WORK_DIR/updated.log"
run_update "1 0 0 0" "$updated_log"

node - "$updated_log" <<'JS'
const fs = require("fs");
const calls = fs.readFileSync(process.argv[2], "utf8").trim().split(/\n+/);
const expected = [
  "subscription/cache:update-request",
  "singbox/runtime:update-providers:"
];

let position = -1;
for (const item of expected) {
  const next = calls.indexOf(item, position + 1);
  if (next === -1) {
    console.error(`missing or out-of-order call: ${item}`);
    console.error(calls.join("\n"));
    process.exit(1);
  }
  position = next;
}
JS

if grep -Eq 'server/service|config/validator|configure-service|init-config|singbox/priority|singbox/dns_failover|reload-sing-box-runtime|write-current-reload-state-clean|run-pending-reload|mark-pending-reload|acquire-runtime-dir-lock-wait' "$updated_log"; then
  fail "subscription update must not stop/reload services, queue a reload, or wait for lifecycle locks"
fi

unchanged_log="$WORK_DIR/unchanged.log"
run_update "0 0 1 0" "$unchanged_log"

grep -Fq 'singbox/runtime:update-providers:1' "$unchanged_log" || fail "unchanged downloads must retry a previously rejected provider update only if pending"
if grep -Eq 'server/service|config/validator|configure-service|init-config|singbox/priority|singbox/dns_failover|reload-sing-box-runtime|write-current-reload-state-clean|run-pending-reload' "$unchanged_log"; then
  fail "unchanged subscription update must not rebuild or reload sing-box"
fi

export FAKE_PROVIDER_FAIL=1
if run_update "1 0 0 0" "$WORK_DIR/rejected.log"; then
  fail "rejected provider update must not report success"
fi
unset FAKE_PROVIDER_FAIL

printf 'subscription update without service reload checks passed\n'
