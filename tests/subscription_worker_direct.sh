#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed '/^let mode = ARGV\[0\]/,$d' "$lib/components/updates.uc" > "$work/worker.uc"
cat >> "$work/worker.uc" <<'UC'
let calls=0,results=[],result=0;
command_status=function(command){die("Production worker must not launch a nested CLI\n");};
subscription_update_common=function(force,section,index){
    if(force!==true || section!="main" || index!="2") die("Worker arguments changed\n");
    calls++;
    return result;
};
finish_subscription_job=function(path,status,output){push(results,status);};
subscription_update_worker("state","output","main","2");
result=1;
subscription_update_worker("state","output","main","2");
if(calls!=2 || results[0]!=0 || results[1]!=1) die("Worker must finalize both success and failure\n");
print("direct subscription worker checks passed\n");
UC
ANTICHEBURNET_BIN=/usr/bin/anticheburnet ANTICHEBURNET_LIB="$lib" ucode -L "$lib" "$work/worker.uc"
