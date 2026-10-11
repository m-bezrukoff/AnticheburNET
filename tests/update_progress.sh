#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$lib/components/action.uc" > "$work/progress.uc"
cat >> "$work/progress.uc" <<'UC'
let path = getenv("ANTICHEBURNET_COMPONENT_PROGRESS_FILE");
update_version = "1.0.7";
for (let stage in [ "checking", "resolving", "downloading", "verifying", "backup", "installing", "restarting", "waiting" ]) {
    if (!report_update_progress(stage, "backend.apk")) die("Unable to write progress\n");
    let value = json(fs.readfile(path));
    if (value.stage != stage || value.version != "1.0.7" || value.detail != "backend.apk") die("Progress payload lost\n");
    if (fs.stat(path + ".tmp") != null) die("Partial progress file was retained\n");
}
UC
ANTICHEBURNET_COMPONENT_PROGRESS_FILE="$work/test.json.progress" ucode -L "$lib" "$work/progress.uc"
printf '{"success":true,"running":true,"kind":"component","component":"anticheburnet","action":"check_and_update","pid":"%s","started_at":%s}\n' "$$" "$(date +%s)" > "$work/test.json"
UPDATES_JOB_DIR="$work" ucode -L "$lib" "$lib/components/updates.uc" component-action-status test > "$work/status"
ucode -e 'let fs=require("fs"); let v=json(fs.readfile(ARGV[0])); if(!v.running || v.progress.stage!="waiting" || v.progress.version!="1.0.7") die("Job status lost progress\n");' "$work/status"
# Confirm the UI response carries the same sidecar without modifying job PID state.
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$lib/service/ui.uc" > "$work/ui.uc"
cat >> "$work/ui.uc" <<'UC'
let items = action_state_from_dir(ARGV[0]);
if (length(items) != 1 || items[0].progress.stage != "waiting") die("UI state lost progress\n");
remove_state_file(ARGV[0] + "/test.json");
if (fs.stat(ARGV[0] + "/test.json.progress")) die("Progress sidecar not cleaned\n");
print("Update progress publication, polling and cleanup checks passed\n");
UC
ucode -L "$lib" "$work/ui.uc" "$work"
