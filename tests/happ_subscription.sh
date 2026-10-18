#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 - "$work" <<'PY'
import base64, json, pathlib, sys
p=pathlib.Path(sys.argv[1])
profile={'Name':'Router test', 'RouteOrder':'block-proxy-direct','GlobalProxy':'true',
 'DirectSites':['domain:example.ru','full:exact.example'], 'DirectIp':['192.0.2.0/24'],
 'ProxySites':['domain:proxy.example'], 'BlockSites':['full:ads.example'],
 'DomainStrategy':'IPIfNonMatch','FakeDNS':'false', 'DnsHosts':{'dns.example':'192.0.2.53'},
 'RemoteDNSDomain':'https://dns.example/dns-query','RemoteDNSIP':'192.0.2.53',
 'DomesticDNSDomain':'https://domestic.example/dns-query','DomesticDNSIP':'198.51.100.53'}
routing='happ://routing/onadd/'+base64.b64encode(json.dumps(profile).encode()).decode()
(p/'headers').write_text('HTTP/1.1 302 Found\nRouting: happ://routing/off\n\nHTTP/1.1 200 OK\nRouting: '+routing+'\nRouting-Enable: true\n')
(p/'profile').write_text(json.dumps(profile))
(p/'body').write_text('hy2://test@example.com:443?ech=QUJDRA==#Happ%20node\n')
(p/'wrapped').write_text(base64.b64encode((routing+'\n'+(p/'body').read_text()).encode()).decode())
(p/'fixture').write_text(json.dumps({'settings':{'.name':'settings','.type':'settings','routing_strategy':'happ','dns_server':'1.1.1.1'},
 'section':[{'.name':'happ_test','.type':'section','enabled':'1','action':'proxy','subscription_urls':['https://example.com/sub'],'subscription_user_agent':'Happ'}]}))
def varint(n):
 r=bytearray()
 while n>127: r.append((n&127)|128); n>>=7
 return bytes(r)+bytes([n])
def field(n,v): return varint(n*8+2)+varint(len(v))+v
cidr=field(1,bytes([192,0,2,0]))+bytes([16,24])
entry=field(2,cidr)+field(1,b'RU') # deliberately nonstandard field order
(p/'geoip.dat').write_bytes(field(1,entry))
domain=bytes([8,2])+field(2,b'example.ru')
(p/'geosite.dat').write_bytes(field(1,field(1,b'RU')+field(2,domain)))
PY
ucode -L "$lib" "$lib/subscription/parser.uc" normalize-content-validated "$work/body" "$work/normalized"
ucode -L "$lib" -e '
let h=require("subscription.happ"),fs=require("fs");
if(!h.attach(ARGV[0],ARGV[1],ARGV[2]))exit(1);
let a=h.extract(fs.readfile(ARGV[0]),fs.readfile(ARGV[1]));
let b=h.extract("",fs.readfile(ARGV[3]));
if(sprintf("%J",a)!=sprintf("%J",b))die("Header and wrapped body differ\n");
if(h.extract("Routing: happ://routing/off","").enabled!==false)exit(1);
let bad=false;try{h.extract("Routing: happ://routing/onadd/!!!","");}catch(e){bad=true;}if(!bad)exit(1);
' "$work/headers" "$work/body" "$work/normalized" "$work/wrapped"
cp "$work/normalized" "$work/previous"
python3 - "$work/normalized" <<'PY'
import json,sys
p=sys.argv[1];v=json.load(open(p));v['happ_routing']['global_proxy']=False;open(p,'w').write(json.dumps(v))
PY
if ucode -L "$lib" "$lib/subscription/parser.uc" runtime-outbounds-equal "$work/previous" "$work/normalized"; then
  echo 'Routing-only change must trigger runtime reload' >&2; exit 1
fi
ucode -L "$lib" -e '
let g=require("routing.geodata"),fs=require("fs");
let a=g.convert(fs.readfile(ARGV[0]),"geoip","ru");if(a.ip_cidr[0]!="192.0.2.0/24")exit(1);
let b=g.convert(fs.readfile(ARGV[1]),"geosite","ru");if(b.domain_suffix[0]!="example.ru")exit(1);
let bad=false;try{g.convert(chr(10)+chr(100),"geoip","ru");}catch(e){bad=true;}if(!bad)exit(1);
' "$work/geoip.dat" "$work/geosite.dat"
mkdir "$work/subscriptions"
cp "$work/previous" "$work/subscriptions/happ_test-subscription-1.json"
printf '%s' https://example.com/sub > "$work/subscriptions/happ_test-subscription-1.url"
printf '%s' Happ > "$work/subscriptions/happ_test-subscription-1.user_agent"
TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture" "$work/config" 127.0.0.1 0 true '' 1.14.1
python3 - "$work/config" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
assert c['dns']['reverse_mapping'] is True
assert 'tproxy6-in' in c['route']['rules'][0]['inbound']
hy=next(o for o in c['outbounds'] if o['type']=='hysteria2')
assert hy['tls']['ech']=={'enabled':True,'config':['-----BEGIN ECH CONFIGS-----','QUJDRA==','-----END ECH CONFIGS-----']}
rules=c['route']['rules']; text=json.dumps(rules)
bt=next(i for i,r in enumerate(rules) if r.get('protocol')=='bittorrent')
assert rules[bt]['outbound']=='direct-out'
assert bt < next(i for i,r in enumerate(rules) if 'example.ru' in json.dumps(r))
for rule in rules:
 if rule.get('type')=='logical' and rule.get('mode')=='and':
  assert rule['rules'][0].get('inbound'), 'Route scope must survive DNS generation'
assert 'example.ru' in text and '192.0.2.0/24' in text and 'ads.example' in text
assert any(r.get('action')=='resolve' and 'server' not in r for r in rules)
servers={s['tag']:s for s in c['dns']['servers']}
remote=next(s for k,s in servers.items() if k.endswith('-happ-remote'))
domestic=next(s for k,s in servers.items() if k.endswith('-happ-domestic'))
assert remote['detour']!=domestic['detour'] and domestic['detour']=='direct-out'
assert remote['domain_resolver'].endswith('-happ-hosts')
assert servers[remote['domain_resolver']]['predefined']['dns.example']==['192.0.2.53']
assert 'fakeip-server' not in json.dumps(c['dns']['rules'][3:])
PY
echo 'Happ routing header/body, policy reload, DAT conversion, DNS and generated routes passed'
# The same subscription must not override the selected-sites method, including
# when the option is absent in an existing configuration.
for method in selected default; do
python3 - "$work/fixture" "$work/selected-fixture" "$method" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]));s=v['section'][0]
if sys.argv[3]=='default': v['settings'].pop('routing_strategy',None)
else: v['settings']['routing_strategy']=sys.argv[3]
s['domain_suffix']=['chosen.example']
open(sys.argv[2],'w').write(json.dumps(v))
PY
TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/selected-fixture" "$work/selected-config" 127.0.0.1 0 true '' 1.14.1
python3 - "$work/selected-config" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
assert c['route']['final']=='direct-out'
assert any(r.get('protocol')=='bittorrent' and r.get('outbound')=='direct-out' for r in c['route']['rules'])
assert '-happ-' not in json.dumps(c)
assert any(r.get('domain_suffix')==['chosen.example'] and r.get('outbound')!='direct-out' for r in c['route']['rules'])
PY
done
mv "$work/subscriptions/happ_test-subscription-1.json" "$work/saved-profile"
python3 - "$work/saved-profile" "$work/subscriptions/happ_test-subscription-1.json" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]));v.pop('happ_routing')
open(sys.argv[2],'w').write(json.dumps(v))
PY
if TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture" "$work/missing-profile" 127.0.0.1 0 true '' 1.14.1 > "$work/missing-log" 2>&1; then
  echo 'HAPP method must reject a missing profile' >&2; exit 1
fi
grep -Fq 'no enabled routing profile' "$work/missing-log"
# Full-tunnel must work without HAPP metadata and must not reuse HAPP DNS or
# destination exclusions. An explicitly selected connection wins over order.
python3 - "$work/selected-fixture" "$work/tunnel-fixture" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]));v['settings'].update(routing_strategy='tunnel',routing_section='happ_test')
v['section'].insert(0,{'.name':'other','.type':'section','action':'connection','enabled':'1','selector_proxy_links':['socks5://127.0.0.1:1080']})
v['section'].insert(0,{'.name':'bypass','.type':'section','action':'bypass','enabled':'1','ip_cidr':['0.0.0.0/0','::/0']})
open(sys.argv[2],'w').write(json.dumps(v))
PY
TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/tunnel-fixture" "$work/tunnel-config" 127.0.0.1 0 true '' 1.14.1
python3 - "$work/tunnel-config" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]));text=json.dumps(c)
assert '-happ-' not in text
assert 'chosen.example' not in json.dumps(c['route']['rules'])
routes=[r for r in c['route']['rules'] if r.get('inbound')==['tproxy-in','tproxy6-in'] and r.get('action')=='route']
catchall=[r for r in routes if set(r)=={'inbound','action','outbound'}]
assert len(catchall)==1
assert 'happ_test' in catchall[0]['outbound'], catchall
assert all(r['outbound']==catchall[0]['outbound'] for r in routes)
assert next(s for s in c['dns']['servers'] if s['tag']=='dns-server')['detour']==catchall[0]['outbound']
bt=next(i for i,r in enumerate(c['route']['rules']) if r.get('protocol')=='bittorrent')
assert c['route']['rules'][bt]['outbound']=='direct-out', 'BitTorrent must remain direct in full tunnel'
assert bt < c['route']['rules'].index(catchall[0]), 'BitTorrent must bypass before the tunnel catch-all'
PY
mv "$work/saved-profile" "$work/subscriptions/happ_test-subscription-1.json"
ucode -L "$lib" -e '
let h=require("singbox.happ");
for(let order in ["block-proxy-direct","block-direct-proxy","proxy-block-direct","proxy-direct-block","direct-block-proxy","direct-proxy-block"]){
 for(let strategy in ["AsIs","IPIfNonMatch","IPOnDemand"]){
  let c={route:{rules:[]}}, groups={};
  for(let kind in ["block","proxy","direct"])groups[kind]={sites:{domain:[kind+".test"]},ips:{ip_cidr:["192.0.2.0/24"]}};
  h.append_routes(c,{profile:{order,strategy,global_proxy:true},groups},{inbound:["test"]},"proxy-test");
  let terminal=[];
  for(let rule in c.route.rules)if(rule.action=="route"||rule.action=="reject")push(terminal,rule.action=="reject"?"block":rule.outbound=="direct-out"?"direct":"proxy");
  if(join("-",slice(terminal,0,3))!=order)die("RouteOrder changed\n");
  if(strategy=="IPOnDemand"&&c.route.rules[0].action!="resolve")die("IPOnDemand must resolve before matching\n");
  if(strategy=="AsIs"&&c.route.rules[length(c.route.rules)-2].action!="resolve")die("AsIs must resolve after selecting the default exit\n");
  for(let rule in c.route.rules)if(rule.action=="resolve"&&rule.server!=null)die("Profile DNS must decide the resolver\n");
  let local={route:{rules:[]},dns:{rules:[]}};
  let policy={profile:{order,strategy,global_proxy:true},groups,host_names:["host.test"],hosts:"hosts",domestic:"domestic",remote:"remote"};
  let exclusions={domain_suffix:["manual.test"]}, scope={inbound:["test"]};
  h.append_routes(local,policy,scope,"proxy-test",exclusions);
  h.append_dns(local,policy,{},exclusions);
  if(local.route.rules[0].action!="resolve"||local.route.rules[1].outbound!="direct-out")die("Manual domains must resolve and bypass before profile rules\n");
  if(local.route.rules[1].rules[0].inbound[0]!="test"||local.route.rules[1].rules[1].domain_suffix[0]!="manual.test")die("Manual exclusions lost their scope or matcher\n");
  if(local.dns.rules[0].server!="hosts"||local.dns.rules[1].server!="domestic")die("Manual exclusions must retain hosts and use direct DNS\n");
  if(scope.inbound[0]!="test"||exclusions.action!=null||exclusions.server!=null)die("Policy generation must not mutate its matchers\n");
 }
}
'
python3 - "$work/fixture" "$work/subscriptions/happ_test-subscription-1.json" <<'PY'
import json,sys
p=sys.argv[1];v=json.load(open(p));s=v['section'][0]
s.update(source_ip_cidr=['192.0.2.20/32'],fully_routed_ips=['192.0.2.21/32'],ports=['80'],domain_suffix=['manual-direct.example','full:exact-direct.example','keyword:manual-keyword','regex:^manual[.]example$'],ip_cidr=['203.0.113.0/24'],community_lists=['ovh','discord'],rule_set=['https://example.com/ignored.srs'],domain_ip_lists=['https://example.com/ignored.lst'])
s.update(mixed_proxy_enabled='1',mixed_proxy_port='1081')
v['section'].insert(0,{'.name':'other','.type':'section','action':'connection','selector_proxy_links':['socks5://127.0.0.1:1080'],'domain_suffix':['other-only.example']})
v['settings']['routing_section']='happ_test'
open(p,'w').write(json.dumps(v))
profile=json.load(open(sys.argv[2]));profile['happ_routing']['global_proxy']=False
open(sys.argv[2],'w').write(json.dumps(profile))
PY
TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture" "$work/scoped-config" 127.0.0.1 0 true '' 1.14.1
python3 - "$work/scoped-config" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
assert not any(i['tag']=='source-dns-in' for i in c['inbounds']), 'Global HAPP must ignore section device conditions'
happ=[r for r in c['dns']['rules'] if '-happ-' in r.get('server','')]
assert happ
assert '192.0.2.20/32' not in json.dumps(happ)
assert '192.0.2.21/32' not in json.dumps(happ)
def check(r):
 assert all(k not in r for k in ['port','port_range','ip_cidr']), 'DNS scope must not contain application matchers'
 for child in r.get('rules',[]):check(child)
for r in happ:check(r)
rules=c['route']['rules']
manual=next((i,r) for i,r in enumerate(rules) if r.get('outbound')=='direct-out' and 'manual-direct.example' in json.dumps(r))
assert manual[1]['rules'][0]['inbound']==['tproxy-in','tproxy6-in']
match=manual[1]['rules'][1]
assert match=={'domain_suffix':['manual-direct.example'],'domain':['exact-direct.example'],'domain_keyword':['manual-keyword'],'domain_regex':['^manual[.]example$']}, match
assert manual[0] < next(i for i,r in enumerate(rules) if 'proxy.example' in json.dumps(r))
assert rules[manual[0]-1]['action']=='resolve' and 'manual-direct.example' in json.dumps(rules[manual[0]-1])
assert any(r.get('outbound')=='direct-out' and r.get('rules',[{}])[0].get('inbound')=='happ_test-mixed-in' and 'manual-direct.example' in json.dumps(r) for r in rules), 'Section listener must honor manual exclusions'
dns=next((i,r) for i,r in enumerate(c['dns']['rules']) if 'manual-direct.example' in json.dumps(r))
assert dns[1]['server'].endswith('-happ-domestic')
assert dns[0] < next(i for i,r in enumerate(c['dns']['rules']) if 'proxy.example' in json.dumps(r))
assert next(s for s in c['dns']['servers'] if s['tag']==dns[1]['server'])['detour']=='direct-out'
assert not any(value in json.dumps(c) for value in ['ignored.srs','ignored.lst','ovh','discord','other-only.example'])
assert '203.0.113.0/24' not in json.dumps(c['route']['rules'])
assert not any(r.get('port')==[80] for r in c['route']['rules']), 'HAPP must own destination selection'
catchall=[r for r in c['route']['rules'] if set(r)=={'action','inbound','outbound'} and r['inbound']==['tproxy-in','tproxy6-in']]
assert len(catchall)==1 and catchall[0]['outbound']!='direct-out', 'Global HAPP strategy must default to the tunnel'
PY
