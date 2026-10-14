#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/subscriptions"
# Exercise the production planner with synthetic URLs, then execute its exact
# shell plan with workers that finish independently (including nonzero results).
sed '/^let mode = ARGV\[0\]/,$d' "$lib/subscription/cache.uc" > "$work/planner.uc"
cat >> "$work/planner.uc" <<'UC'
connections.subscription_urls = function(section) { return [ "https://a.test", "https://b.test", "https://c.test" ]; };
system = function(command) {
    if (index(command, "update-source") >= 0) print(command, "\n");
    return 0;
};
update_subscription_sources_parallel({ ".name": "proxy" }, true);
UC
ucode_bin="$(command -v ucode)"
ANTICHEBURNET_LIB="$lib" TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" "$ucode_bin" -L "$lib" "$work/planner.uc" > "$work/plan.sh"
events="$work/events.tsv"
: > "$events"
ucode() {
  local index="$6" delay code
  case "$index" in 1) delay=0.4; code=0 ;; 2) delay=0.1; code=2 ;; 3) delay=0.2; code=1 ;; *) return 64 ;; esac
  printf '%s\tstart\t%s\n' "$index" "$(date +%s.%N)" >> "$events"
  sleep "$delay"
  printf '{"source":%s}\n' "$index" > "$9"
  printf '%s\tfinish\t%s\n' "$index" "$(date +%s.%N)" >> "$events"
  return "$code"
}
source "$work/plan.sh"
node - "$events" "$work/subscriptions" <<'JS'
const fs = require('fs'), assert = require('assert/strict');
const events = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(line => { const [source, phase, seconds] = line.split('\t'); return {source, phase, seconds:Number(seconds)}; });
const starts = events.filter(e => e.phase === 'start'), finishes = events.filter(e => e.phase === 'finish');
assert.equal(starts.length, 3); assert.equal(finishes.length, 3);
assert(Math.max(...starts.map(e => e.seconds)) < Math.min(...finishes.map(e => e.seconds)), 'subscription sources must start concurrently');
assert(finishes.find(e => e.source === '2').seconds < finishes.find(e => e.source === '1').seconds, 'sources must complete independently');
const results = fs.readdirSync(process.argv[3]).filter(name => name.includes('update-result')).map(name => [name.match(/subscription-(\d+)/)[1], fs.readFileSync(`${process.argv[3]}/${name}`, 'utf8').trim()]).sort();
assert.deepEqual(results.map(e => e[1]), ['0', '2', '1']);
JS

# Exercise the production collector too: planning alone cannot catch runtime
# errors while reading worker status files and aggregating source metadata.
sed '/^let mode = ARGV\[0\]/,$d' "$lib/subscription/cache.uc" > "$work/collector.uc"
cat >> "$work/collector.uc" <<'UC'
let worker_statuses = [], collected_metadata = [], cached_metadata = [];
let timestamp_written = false, metadata_superseded = false, worker_records = [];
let test_dir = getenv("TMP_SUBSCRIPTION_FOLDER");
ensure_runtime_dirs = function() {};
log_message = function(message, level) {};
temp_path = function(dir, section, suffix) { return dir + "/" + section + "." + suffix; };
connections.subscription_urls = function(section) { return [ "https://fixture.test" ]; };
update_subscription_sources_parallel = function(section, force) {
    worker_records = [];
    for (let status in worker_statuses) {
        let source_section = source_id("proxy", length(worker_records) + 1);
        let record = {
            source_section,
            result_path: test_dir + "/" + source_section + ".result",
            metadata_path: test_dir + "/" + source_section + ".metadata",
            skipped: status == "skipped"
        };
        if (status != null && !record.skipped) write_text(record.result_path, status);
        if (!record.skipped) write_json(record.metadata_path, {});
        push(worker_records, record);
    }
    return worker_records;
};
append_metadata_file = function(path, metadata_path, source_index, source_section) {
    push(collected_metadata, source_index);
};
append_available_cached_metadata = function(path, section, source_index, source_section) {
    push(cached_metadata, source_index);
};
finalize_subscription_section_metadata = function(section, path, superseded) {
    metadata_superseded = superseded;
    unlink_path(path);
};
write_subscription_update_timestamp = function(section) { timestamp_written = true; };

function check_case(statuses, expected_result, expected_metadata, expected_cached, expected_timestamp, expected_superseded) {
    worker_statuses = statuses;
    collected_metadata = [];
    cached_metadata = [];
    timestamp_written = false;
    metadata_superseded = false;
    let result = subscription_update_section({ ".name": "proxy", action: "proxy" }, true);
    if (result != expected_result ||
        sprintf("%J", collected_metadata) != sprintf("%J", expected_metadata) ||
        sprintf("%J", cached_metadata) != sprintf("%J", expected_cached) ||
        timestamp_written != expected_timestamp || metadata_superseded != expected_superseded)
        die("Incorrect subscription result aggregation for " + sprintf("%J", statuses) + "\n");
    for (let record in worker_records)
        if (fs.stat(record.result_path) != null || fs.stat(record.metadata_path) != null)
            die("Worker temporary files were not removed\n");
}

check_case([ "0\n", "2\n", "1\n" ], 0, [ 1, 2 ], [ 3 ], true, false);
check_case([ " \t0\r\n" ], 0, [ 1 ], [], true, false);
check_case([ "2\n" ], 2, [ 1 ], [], true, false);
check_case([ "1\n" ], 1, [], [ 1 ], false, false);
check_case([ "4\n" ], 4, [], [], false, true);
check_case([ "0\n", "4\n" ], 0, [ 1 ], [], true, true);
check_case([ "", null, "unexpected\n" ], 1, [], [ 1, 2, 3 ], false, false);
check_case([ "skipped", "2\n" ], 2, [ 2 ], [ 1 ], true, false);
print("subscription worker result aggregation checks passed\n");
UC
ANTICHEBURNET_LIB="$lib" TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" "$ucode_bin" -L "$lib" "$work/collector.uc"
printf 'parallel subscription starts and independent completion checks passed\n'
