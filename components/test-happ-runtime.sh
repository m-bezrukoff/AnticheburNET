#!/usr/bin/env bash
# Check the generated subscription policy with the exact packed ARM64 core.
set -euo pipefail
work="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/forkop/files/usr/lib"
test_dir=$(mktemp -d)
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  ip address del 192.0.2.1/32 dev lo 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT
ip address add 192.0.2.1/32 dev lo
qemu-aarch64 "$work/sing-box.arm64" generate ech-keypair public.test > "$test_dir/ech.pem"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
  -addext 'subjectAltName=DNS:localhost,DNS:public.test' \
  -keyout "$test_dir/key.pem" -out "$test_dir/cert.pem" >/dev/null 2>&1
python3 - "$test_dir" <<'PY'
import base64,json,pathlib,re,sys,urllib.parse
p=pathlib.Path(sys.argv[1]);pem=(p/'ech.pem').read_text()
config=re.search(r'-----BEGIN ECH CONFIGS-----\s*(.*?)\s*-----END ECH CONFIGS-----',pem,re.S).group(1)
key=re.search(r'-----BEGIN ECH KEYS-----.*?-----END ECH KEYS-----',pem,re.S).group()
profile={'Name':'ARM64 runtime', 'DirectSites':['domain:direct.test'], 'DirectIp':['geoip:ru'],
 'BlockSites':['full:blocked.direct.test'], 'ProxySites':['full:proxy.direct.test'],
 'RemoteDNSType':'DoU','RemoteDNSIP':'127.0.0.1','DomesticDNSType':'DoU','DomesticDNSIP':'127.0.0.1',
 'DomainStrategy':'IPIfNonMatch','GlobalProxy':'true','RouteOrder':'block-proxy-direct',
 'Geoipurl':'http://127.0.0.1:18081/geoip.dat','DnsHosts':{'hosts.test':'127.0.0.1'}}
(p/'routing-header').write_text('happ://routing/onadd/'+base64.b64encode(json.dumps(profile).encode()).decode())
link='hy2://local-test@127.0.0.1:18445?'+urllib.parse.urlencode({'sni':'localhost','insecure':'1','ech':config.replace('\n','')})+'#Happ-runtime'
(p/'subscription').write_text(base64.b64encode(link.encode()).decode())
(p/'fixture').write_text(json.dumps({'settings':{'.name':'settings','.type':'settings','dns_server':'1.1.1.1','dns_type':'udp','cache_path':str(p/'cache.db')},
 'section':[{'.name':'happ_runtime','.type':'section','enabled':'1','action':'proxy','subscription_urls':['http://127.0.0.1:18081/subscription'],
 'source_ip_cidr':['127.0.0.1/32'],'fully_routed_ips':['127.0.0.3/32'],'ports':['18081'],
 'subscription_user_agent':'Happ','mixed_proxy_enabled':'1','mixed_proxy_port':'10823'}]}))
(p/'server.json').write_text(json.dumps({'dns':{'servers':[{'type':'hosts','tag':'fixture-dns','predefined':{name:'127.0.0.1' for name in ['www.direct.test','proxy.direct.test','other.test','hosts.test']}}],'final':'fixture-dns'},
 'route':{'default_domain_resolver':'fixture-dns'},'inbounds':[{'type':'hysteria2','listen':'127.0.0.1','listen_port':18445,'users':[{'password':'local-test'}],
 'tls':{'enabled':True,'certificate_path':str(p/'cert.pem'),'key_path':str(p/'key.pem'),'ech':{'enabled':True,'key':[key]}}}],
 'outbounds':[{'type':'direct','inet4_bind_address':'127.0.0.2'}]}))
def field(n,v):
 def vi(i):
  r=bytearray()
  while i>127:r.append((i&127)|128);i>>=7
  return bytes(r)+bytes([i])
 return vi(n*8+2)+vi(len(v))+v
cidr=field(1,bytes([192,0,2,0]))+bytes([16,24])
(p/'geoip.dat').write_bytes(field(1,field(1,b'RU')+field(2,cidr)))
PY
python3 "$root/components/test-happ-runtime.py" "$test_dir" > "$test_dir/http.log" 2>&1 &
pids+=("$!")
for attempt in {1..30}; do curl -fsS http://127.0.0.1:18081/subscription >/dev/null && break; sleep 0.2; done
mkdir "$test_dir/subscriptions"
curl -fsS --user-agent Happ --dump-header "$test_dir/headers" http://127.0.0.1:18081/subscription -o "$test_dir/body"
normalized="$test_dir/subscriptions/happ_runtime-subscription-1.json"
ucode -L "$lib" "$lib/subscription/parser.uc" normalize-content-validated "$test_dir/body" "$normalized"
ucode -L "$lib" -e 'if(!require("subscription.happ").attach(ARGV[0],ARGV[1],ARGV[2]))exit(1);' "$test_dir/headers" "$test_dir/body" "$normalized"
printf '%s' http://127.0.0.1:18081/subscription > "$test_dir/subscriptions/happ_runtime-subscription-1.url"
printf '%s' Happ > "$test_dir/subscriptions/happ_runtime-subscription-1.user_agent"
TMP_SUBSCRIPTION_FOLDER="$test_dir/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$test_dir/fixture" "$test_dir/client.json" 127.0.0.1 0 true '' 1.14.1
qemu-aarch64 "$work/sing-box.arm64" check -c "$test_dir/client.json"
# Bind the direct exit differently from the encrypted proxy's exit: the HTTP
# fixture reports its real peer address, proving which route carried the request.
# QEMU user mode lacks IP_TRANSPARENT. Keep the full generated config check,
# then exercise the same policy through its mixed proxy and actual DNS inbounds.
python3 - "$test_dir/client.json" <<'PY'
import json,sys
p=sys.argv[1];v=json.load(open(p));next(o for o in v['outbounds'] if o['tag']=='direct-out')['inet4_bind_address']='127.0.0.1'
v['inbounds']=[i for i in v['inbounds'] if i['type']!='tproxy']
open(p,'w').write(json.dumps(v))
PY
for role in server client; do
  qemu-aarch64 "$work/sing-box.arm64" check -c "$test_dir/$role.json"
  qemu-aarch64 "$work/sing-box.arm64" run -c "$test_dir/$role.json" > "$test_dir/$role.log" 2>&1 &
  pids+=("$!")
done
ready=0
for attempt in {1..30}; do
  if [[ "$(curl --noproxy '' -fsS --max-time 3 --socks5-hostname 127.0.0.1:10823 http://www.direct.test:18081/source 2>/dev/null || true)" == 127.0.0.1 ]]; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || { cat "$test_dir/"*.log; exit 1; }
for pair in 'www.direct.test 127.0.0.1' 'proxy.direct.test 127.0.0.2' 'other.test 127.0.0.2' 'geo.test 127.0.0.1' 'hosts.test 127.0.0.2'; do
  read -r domain expected <<< "$pair"
  actual=$(curl --noproxy '' -fsS --max-time 15 --socks5-hostname 127.0.0.1:10823 "http://$domain:18081/source") || { cat "$test_dir/"*.log; exit 1; }
  [[ "$actual" == "$expected" ]] || { echo "Wrong route for $domain: $actual" >&2; exit 1; }
done
if curl --noproxy '' -fsS --max-time 4 --socks5-hostname 127.0.0.1:10823 http://blocked.direct.test:18081/source; then
  echo 'Blocked Happ domain was reachable' >&2; exit 1
fi
# Real-address DNS must retain its domain for subsequent IP-only router traffic.
python3 - <<'PY'
import socket,struct
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.settimeout(5)
for name in ['hosts.test','www.direct.test']:
 labels=b''.join(bytes([len(label)])+label.encode() for label in name.split('.'))+b'\x00'
 query=struct.pack('!HHHHHH',0x1234,0x100,1,0,0,0)+labels+struct.pack('!HH',1,1)
 s.sendto(query,('127.0.0.42',53));response=s.recv(4096)
 assert response[:2]==b'\x12\x34' and response[3]&15==0 and response[-4:]==bytes([127,0,0,1])
PY
[[ "$(curl --noproxy '' -fsS --max-time 10 --socks5-hostname 127.0.0.1:10823 http://127.0.0.1:18081/source)" == 127.0.0.1 ]]
echo 'ARM64 Happ header, DNS, ECH Hysteria2, block/proxy/direct priority and GeoIP after resolution passed'
