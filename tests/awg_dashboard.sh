#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ucode -L "$lib" "$root/tests/awg_dashboard.uc" "$work/body" "$work/normalized"
mkdir "$work/subscriptions"
cp "$work/normalized" "$work/subscriptions/main-subscription-1.json"
printf '%s\n' https://example.com/sub > "$work/subscriptions/main-subscription-1.url"
printf '%s\n' Happ > "$work/subscriptions/main-subscription-1.user_agent"
cat > "$work/fixture" <<'JSON'
{"settings":{".name":"settings",".type":"settings","dns_server":"1.1.1.1"},"section":[{".name":"main",".type":"section","enabled":"1","action":"proxy","subscription_urls":["https://example.com/sub"],"subscription_user_agent":"Happ"}]}
JSON
TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture" "$work/generated" 127.0.0.1 0 true '' 1.14.1
python3 - "$work/generated" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); c=json.loads(p.read_text())
nodes=[o for o in c['outbounds'] if o.get('bind_interface')=='acawg1']
assert len(nodes)==1 and nodes[0]['type']=='direct'
tag=nodes[0]['tag']
assert tag in next(o for o in c['outbounds'] if o['tag']=='main-out')['outbounds']
assert not any('__awg_config' in o for o in c['outbounds'])
manifest=json.loads(pathlib.Path(str(p)+'.awg.json').read_text())
assert len(manifest)==1 and manifest[0]['table']==312
assert 'HeaderProtectionKey = ' in manifest[0]['config']
metadata=json.loads(pathlib.Path(str(p)+'.section-cache/main.json').read_text())['outboundMetadata']
assert metadata['protocols'][tag]=='amneziawg'
assert metadata['transports'][tag]=='udp'
assert pathlib.Path(str(p)+'.awg.json').stat().st_mode & 0o777 == 0o600
PY
