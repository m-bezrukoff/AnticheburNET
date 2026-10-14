#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/cache.uc" <<'UC'
let fs=require("fs"),geo=require("routing.geodata"),happ=require("singbox.happ");
let source="first",calls=0,directory=ARGV[0];
geo.source_path=function(url,dir,kind) {
    fs.writefile(dir+"/"+kind+".dat",source);
    return dir+"/"+kind+".dat";
};
geo.convert=function(data,kind,code) {
    calls++;
    return {ip_cidr:[data=="first"?"192.0.2.0/24":"198.51.100.0/24"]};
};
let profile=require("subscription.happ").normalize({DirectIp:["geoip:ru"]});
function prepare() {
    let config={dns:{servers:[]},route:{rule_set:[]}};
    happ.prepared(config,profile,"test-out",directory);
    return config.route.rule_set[0].path;
}
let original=prepare();
if(calls!=1 || prepare()!=original || calls!=1) die("Warm geodata must reuse converted rules\n");
source="other"; // same byte length: file-size-only caches must not match.
let changed=prepare();
if(calls!=2 || changed==original) die("DAT content changes must invalidate conversion\n");
if(fs.readfile(original)==null) die("Previous active rules must remain available for rollback\n");
fs.writefile(changed,"corrupt");
if(prepare()!=changed || calls!=3 || fs.readfile(changed)=="corrupt") die("Corrupt rules must be rebuilt\n");
fs.unlink(changed);
prepare();
if(calls!=4) die("Missing rules must be rebuilt\n");
profile.geoip_url="https://other.test/geoip.dat";
prepare();
if(calls!=5) die("Source URL changes must invalidate conversion\n");
profile.rules.direct.ips=["geoip:de"];
prepare();
if(calls!=6) die("Different geodata codes must have independent caches\n");
for(let path in fs.glob(directory+"/*.cache.json")) {
    if((fs.stat(path).mode&0777)!=0600) die("Cache metadata must be private\n");
    fs.writefile(path,"invalid json");
}
prepare();
if(calls!=7) die("Corrupt cache metadata must not be trusted\n");
print("Happ geodata conversion cache checks passed\n");
UC
ucode -L "$lib" "$work/cache.uc" "$work"
