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
printf 'parallel subscription starts and independent completion checks passed\n'
