#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/forkop/files/usr/lib"
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
(p/'fixture').write_text(json.dumps({'settings':{'.name':'settings','.type':'settings','dns_server':'1.1.1.1'},
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
hy=next(o for o in c['outbounds'] if o['type']=='hysteria2')
assert hy['tls']['ech']=={'enabled':True,'config':['-----BEGIN ECH CONFIGS-----','QUJDRA==','-----END ECH CONFIGS-----']}
rules=c['route']['rules']; text=json.dumps(rules)
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
