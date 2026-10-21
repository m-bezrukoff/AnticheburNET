#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq "option routing_strategy 'tunnel'" "$root/anticheburnet/files/etc/config/anticheburnet" || {
 echo 'New installations must default to full tunnel' >&2; exit 1;
}
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
let route=require("singbox.route");
for(let mode in ["selected","happ","tunnel"]){
 let config=route.config({routing_strategy:mode},{}), matches=[];
 for(let rule in config.rules)
  if(rule.protocol=="bittorrent")push(matches,rule);
 if(length(matches)!=1||matches[0].action!="route"||matches[0].outbound!="direct-out")
  die("Torrent traffic must remain direct in every routing strategy\n");
 let smtp=[];
 for(let rule in config.rules)
  if(rule.port!=null)push(smtp,rule);
 if(mode=="happ"){
  if(length(smtp)!=1||smtp[0].action!="route"||smtp[0].network!="tcp"||
     smtp[0].outbound!="direct-out"||length(smtp[0].port)!=3||
     smtp[0].port[0]!=25||smtp[0].port[1]!=465||smtp[0].port[2]!=587)
   die("HAPP must route SMTP ports directly for IPv4 and IPv6\n");
  if(smtp[0].ip_version!=null)
   die("SMTP bypass must cover both IP versions\n");
 }else if(length(smtp)!=0)
  die("SMTP bypass must not change other routing strategies\n");
}
print("Routing strategy selection checks passed\n");
'
