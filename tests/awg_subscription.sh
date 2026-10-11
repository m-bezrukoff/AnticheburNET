#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
component="$root/components/awg/files/usr/lib"
parser="$component/anticheburnet-components/awg-subscription.uc"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 - "$work" <<'PY'
import base64,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); key=base64.b64encode(bytes(range(32))).decode()
node={'type':'wireguard','tag':'AWG #1','address':['10.7.0.2/32','fd00:7::2/128'],'private_key':key,
 'amnezia':{'version':3,'jc':6,'h1':'100-200','header_protection_key':key,'random_trailers':True,'disable_cookies':True},
 'peers':[{'address':'vpn.example','port':443,'public_key':key,'allowed_ips':['0.0.0.0/0','::/0'],'persistent_keepalive_interval':'20-30'}]}
(p/'native').write_text(json.dumps({'endpoints':[node]}))
(p/'base64').write_text(base64.b64encode((p/'native').read_bytes()).decode())
clash={'type':'wireguard','name':'AWG #1','ip':'10.7.0.2','ipv6':'fd00:7::2','private-key':key,'public-key':key,'server':'vpn.example','port':443,
 'amnezia-wg-option':{'version':3,'jc':6,'h1':'100-200','header-protection-key':key,'random-trailers':True,'disable-cookies':True},'persistent-keepalive':'20-30'}
(p/'mihomo').write_text(json.dumps({'proxies':[clash]}))
(p/'yaml').write_text(f'''proxies:
  - name: "AWG #1"
    type: wireguard
    ip: 10.7.0.2
    ipv6: fd00:7::2
    private-key: {key}
    public-key: {key}
    server: vpn.example
    port: 443
    persistent-keepalive: 20-30
    amnezia-wg-option:
      version: 3
      jc: 6
      h1: 100-200
      header-protection-key: >-
        {key[:22]}
        {key[22:]}
      random-trailers: true
      disable-cookies: true
''')
other=json.loads(json.dumps(node));other['tag']='AWG #2'
(p/'multiple').write_text(json.dumps({'endpoints':[node,other]}))
bad=json.loads(json.dumps(node));bad['amnezia']['unsupported']=1
(p/'bad-option').write_text(json.dumps(bad))
bad=json.loads(json.dumps(node));bad['private_key']='invalid'
(p/'bad-key').write_text(json.dumps(bad))
bad=json.loads(json.dumps(node));bad['amnezia']['i1']='hello\nPreUp = malicious'
(p/'bad-injection').write_text(json.dumps(bad))
(p/'absent').write_text('hy2://pw@example.com:443#no-awg')
(p/'headers').write_text('Routing: happ://routing/onadd/'+base64.b64encode(json.dumps({'DirectSites':['domain:example.ru']}).encode()).decode())
PY
uc() { ucode -L "$lib" -L "$component/anticheburnet-components" "$parser" "$@"; }
for format in native base64 mihomo yaml; do
  uc list "$work/$format" | grep -Fq 'AWG #1'
  uc extract "$work/$format" "$work/$format.conf" 'AWG #1' "$work/headers"
  grep -Fqx 'HeaderProtectionKey = AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=' "$work/$format.conf"
  grep -Fqx 'RandomTrailers = on' "$work/$format.conf"
  grep -Fqx 'DisableCookies = on' "$work/$format.conf"
  grep -Fq '# AnticheburNET-Happ-Routing = ' "$work/$format.conf"
  [[ $(stat -c '%a' "$work/$format.conf") == 600 ]]
done
uc extract "$work/native.conf" "$work/ini.conf" AmneziaWG
uc extract "$work/multiple" "$work/selected.conf" 'AWG #2'
for input in absent multiple bad-option bad-key bad-injection; do
  if uc extract "$work/$input" "$work/rejected.conf" 2>/dev/null; then
    echo "Unexpected AWG import success for $input" >&2; exit 1
  fi
done
if uc url 'file:///etc/shadow' 2>/dev/null; then exit 1; fi
cat > "$work/fixture" <<'JSON'
{"settings":{".name":"settings",".type":"settings","dns_server":"1.1.1.1"},"section":[{".name":"awg_policy",".type":"section","enabled":"1","action":"connection","interfaces":["awg0"]}]}
JSON
printf '%s\n' 'anticheburnet_awg.settings=settings' 'anticheburnet_awg.settings.interface=awg0' "anticheburnet_awg.settings.config_file=$work/native.conf" > "$work/uci-state"
ANTICHEBURNET_UCI_STATE_FILE="$work/uci-state" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture" "$work/generated" 127.0.0.1 0 true '' 1.14.1
python3 - "$work/generated" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]));assert any(o.get('bind_interface')=='awg0' for o in c['outbounds'])
assert 'example.ru' in json.dumps(c['route']['rules'])
assert any(s['tag'].endswith('-happ-remote') for s in c['dns']['servers'])
assert c['dns']['reverse_mapping'] is True
PY
echo 'AWG INI/base64/native JSON/Mihomo JSON/YAML selection, routing, permissions and rejection checks passed'
