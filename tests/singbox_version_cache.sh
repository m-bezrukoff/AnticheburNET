#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/version.uc" <<'UC'
let fs=require("fs"),version=require("singbox.version");
let binary=ARGV[0]+"/sing-box",cache=ARGV[0]+"/cache/version.json",probes=0,output="sing-box version 1.14.1-extended\nTags: with_utls\n";
fs.writefile(binary,"first binary");
fs.popen=function(command,mode) {
    if(index(command,"sha256sum ")==0) {
        let bytes=fs.readfile(binary),sum=0;
        for(let i=0;i<length(bytes);i++) sum+=ord(bytes,i)*(i+1);
        return {read:function(){return sprintf("%064x",sum);},close:function(){return 0;}};
    }
    probes++;
    return {read:function(){return output;},close:function(){return 0;}};
};
if(version.get(binary,cache).version!="1.14.1-extended" || probes!=1) die("First version must be probed\n");
if(version.get(binary,cache).output!=output || probes!=1) die("Warm version must use cached output\n");
fs.writefile(binary,"replacement binary");
output="sing-box version 1.14.2-extended\n";
if(version.get(binary,cache).version!="1.14.2-extended" || probes!=2) die("Binary changes must invalidate version\n");
fs.writefile(cache,"broken json");
if(version.get(binary,cache).version!="1.14.2-extended" || probes!=3) die("Corrupt version cache must be reprobed\n");
fs.writefile(binary,"failed replacement");
output="";
if(version.get(binary,cache)!=null || probes!=4) die("Failed probe must not return an old version\n");
fs.unlink(binary);
if(version.get(binary,cache)!=null || probes!=4) die("Missing binary must not be probed or cached\n");
print("sing-box executable version cache checks passed\n");
UC
ucode -L "$lib" "$work/version.uc" "$work"
