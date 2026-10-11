#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT_DIR/anticheburnet/files/usr/lib"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$WORK_DIR/bin" "$WORK_DIR/latency-actions"
cat >"$WORK_DIR/bin/curl" <<'SH'
#!/usr/bin/env sh
for arg do
  case "$arg" in
    *:9090/proxies)
      printf '%s\n' '{"proxies":{"group-a":{"type":"URLTest"},"group-b":{"type":"urltest"}}}'
      exit 0 ;;
    */delay) tag="${arg%/delay}"; tag="${tag##*/}" ;;
  esac
done
printf 'start %s\n' "$tag" >>"$LATENCY_EVENTS"
if [ "$tag" = 'proxy-0' ]; then
  # A slow first response must allow later probes to finish and report progress.
  sleep 1
else
  sleep 0.1
fi
printf 'end %s\n' "$tag" >>"$LATENCY_EVENTS"
case "$tag" in
  transport-failure) printf '%s\n' '{"delay":1}'; exit 28 ;;
  invalid-json) printf '%s\n' 'invalid json'; exit 0 ;;
  *) printf '%s\n' '{"delay":1}' ;;
esac
SH
chmod +x "$WORK_DIR/bin/curl"
printf '%s\n' 'anticheburnet.settings=settings' >"$WORK_DIR/uci-state"
state="$WORK_DIR/latency-actions/job.json"
printf '%s\n' '{"success":true,"running":true,"kind":"latency","started_at":100}' >"$state"
tags='["group-a","proxy-0","proxy-1","proxy-2","proxy-3","proxy-4","proxy-5","proxy-6","proxy-7","proxy-8","proxy-9","transport-failure","invalid-json","group-b"]'

LATENCY_EVENTS="$WORK_DIR/events" \
ANTICHEBURNET_UCI_STATE_FILE="$WORK_DIR/uci-state" \
ANTICHEBURNET_LIB="$LIB_DIR" \
ANTICHEBURNET_UI_LATENCY_ACTION_DIR="$WORK_DIR/latency-actions" \
PATH="$WORK_DIR/bin:$PATH" \
  ucode -L "$LIB_DIR" "$LIB_DIR/diagnostics/runtime.uc" clash-api get_proxy_latencies "$tags" 5000 "$state" >"$WORK_DIR/result" &
worker=$!

progress_seen=0
for attempt in $(seq 1 40); do
  if JOB_STATE="$state" node - <<'NODE'
const fs = require('fs');
try {
  const progress = JSON.parse(fs.readFileSync(process.env.JOB_STATE, 'utf8')).progress;
  process.exit(progress && progress.completed > 0 && progress.completed < 8 ? 0 : 1);
} catch { process.exit(1); }
NODE
  then
    progress_seen=1
    break
  fi
  sleep 0.02
done
status=0
wait "$worker" || status=$?
[ "$status" = 1 ] || fail "mixed latency failures must produce exit code 1"
[ "$progress_seen" = 1 ] || fail "fast responses must update progress before the slow first response"

node - "$WORK_DIR/events" "$state" "$WORK_DIR/result" <<'NODE'
const assert = require('assert/strict');
const fs = require('fs');
const active = new Set();
const completed = new Set();
let peak = 0;
for (const line of fs.readFileSync(process.argv[2], 'utf8').trim().split('\n')) {
  const [event, tag] = line.split(' ');
  if (event === 'start') {
    assert(!active.has(tag) && !completed.has(tag), 'each tag must run once');
    if (tag.startsWith('group-')) {
      assert.equal([...completed].filter(t => !t.startsWith('group-')).length, 12,
        'URLTest probes must wait for all ordinary proxies');
    }
    active.add(tag);
    peak = Math.max(peak, active.size);
  } else {
    assert(active.delete(tag), 'each completion must belong to an active probe');
    completed.add(tag);
  }
}
assert.equal(peak, 8, 'probe concurrency must reach and never exceed eight');
assert.equal(active.size, 0);
assert.equal(completed.size, 14);
const progress = JSON.parse(fs.readFileSync(process.argv[3], 'utf8')).progress;
assert.deepEqual(progress, {completed: 14, total: 14, failed: 2});
const result = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
assert.deepEqual(result, {success: false, count: 14, failed: true});
NODE

printf 'PASS: bounded asynchronous latency probes, live progress and mixed failures\n'
