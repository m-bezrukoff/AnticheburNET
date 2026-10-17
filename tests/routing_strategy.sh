#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ucode -L "$root/anticheburnet/files/usr/lib" -e '
let s=require("routing.strategy");
let sections=[
 {".name":"bypass",action:"bypass"},
 {".name":"disabled",action:"connection",enabled:"0"},
 {".name":"one",action:"connection"},
 {".name":"two",action:"proxy"}
];
if(s.mode({})!="selected"||s.global_tunnel({}))die("Default must be direct with exceptions\n");
for(let mode in ["happ","tunnel"])
 if(!s.global_tunnel({routing_strategy:mode}))die("Missing global interception\n");
if(s.tunnel_section({},sections)[".name"]!="one")die("Wrong automatic tunnel\n");
if(s.tunnel_section({routing_section:"two"},sections)[".name"]!="two")die("Explicit tunnel ignored\n");
for(let name in ["disabled","bypass","missing"])
 if(s.tunnel_section({routing_section:name},sections)!=null)die("Invalid tunnel must not fall back\n");
if(s.tunnel_section({},[])!=null)die("Empty connections must not pick a tunnel\n");
print("Routing strategy selection checks passed\n");
'
