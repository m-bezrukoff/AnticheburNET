#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/subscriptions" "$work/bin"

# Include an imported socket mark, TLS settings, an explicit subscription chain
# and a URLTest group. Only the terminal server sockets may receive Dial Fields.
cat >"$work/subscriptions/main-subscription-1.json" <<'JSON'
{"outbounds":[
 {"type":"vless","tag":"tls-node","server":"one.example","server_port":443,
  "uuid":"00000000-0000-4000-8000-000000000001","routing_mark":1,
  "tls":{"enabled":true,"server_name":"certificate.example","insecure":false}},
 {"type":"hysteria2","tag":"udp-node","server":"two.example","server_port":443,
  "password":"fixture","tls":{"enabled":true,"server_name":"two.example"}},
 {"type":"socks","tag":"relay","server":"relay.example","server_port":1080},
 {"type":"trojan","tag":"chained","server":"three.example","server_port":443,
  "password":"fixture","detour":"relay","tls":{"enabled":true}},
 {"type":"urltest","tag":"auto","outbounds":["tls-node","udp-node"],
  "url":"https://health.example/generate_204","__anticheburnet_allow_group":true}
]}
JSON
printf '%s' 'https://subscription.example/nodes' >"$work/subscriptions/main-subscription-1.url"
: >"$work/subscriptions/main-subscription-1.user_agent"
ucode -L "$lib" -e '
let fs = require("fs"), happ = require("subscription.happ");
let value = json(fs.readfile(ARGV[0]));
value.happ_routing = happ.normalize({ DirectSites: ["domain:domestic.example"] });
fs.writefile(ARGV[0], sprintf("%J", value));
' "$work/subscriptions/main-subscription-1.json"

cat >"$work/bin/nft" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$NFT_TEST_LOG"
SH
chmod +x "$work/bin/nft"

for strategy in selected happ tunnel; do
  cat >"$work/fixture.json" <<JSON
{"settings":{".name":"settings",".type":"settings","routing_strategy":"$strategy",
 "dns_server":"1.1.1.1","bootstrap_dns_server":"9.9.9.9"},
 "section":[{".name":"main",".type":"section","enabled":"1","action":"connection",
 "subscription_urls":["https://subscription.example/nodes"]}]}
JSON
  for version in 1.14.1 1.14.3-extended-2.7.3-anticheburnet.7; do
    output="$work/$strategy-$version.json"
    TMP_SUBSCRIPTION_FOLDER="$work/subscriptions" \
      ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture \
        "$work/fixture.json" "$output" 127.0.0.1 0 true '' "$version"

    python3 - "$output" "$strategy" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text())
provider = pathlib.Path(str(path) + '.providers.json')
outbounds = json.loads(provider.read_text())['outbounds'] if provider.exists() else config['outbounds']
nodes = {item['tag']: item for item in outbounds}
bypass = 0x08000000
assert config['route']['default_mark'] == bypass
assert config['route']['default_domain_resolver'] == (
    'dns-server' if sys.argv[2] == 'selected' else 'bootstrap-dns-server')
bootstrap = next(s for s in config['dns']['servers'] if s['tag'] == 'bootstrap-dns-server')
assert bootstrap['server'] == '9.9.9.9' and bootstrap.get('detour') is None
assert bootstrap['routing_mark'] == bypass
for tag in ['tls-node', 'udp-node', 'relay']:
    if sys.argv[2] == 'selected':
        assert nodes[tag].get('routing_mark') == (1 if tag == 'tls-node' else None)
    else:
        assert nodes[tag]['routing_mark'] == bypass, (sys.argv[2], tag)
    assert nodes[tag].get('detour') is None, 'A probe must dial its own server directly'
assert nodes['tls-node']['tls'] == {
    'enabled': True, 'server_name': 'certificate.example', 'insecure': False}
assert nodes['chained']['detour'] == 'relay', 'Keep explicitly configured subscription chains'
assert 'routing_mark' not in nodes['chained']
assert 'routing_mark' not in nodes['auto']
assert nodes['auto']['outbounds'] == ['tls-node', 'udp-node']
assert nodes['auto']['url'] == 'https://health.example/generate_204'
assert set(nodes['main-out']['outbounds']) >= {'chained', 'auto'}
PY
  done

  : >"$work/$strategy.nft"
  NFT_TEST_LOG="$work/$strategy.nft" PATH="$work/bin:$PATH" \
    ucode -L "$lib" "$lib/nft/apply.uc" nft-add-happ-real-ip-rules-fixture \
      "$work/fixture.json" TestTable interfaces 0x04000000
  if [ "$strategy" = selected ]; then
    [ ! -s "$work/$strategy.nft" ]
    continue
  fi
  for protocol in tcp udp; do
    grep -Fq "mangle_output meta mark 0 meta l4proto $protocol meta mark set 0x04000000" "$work/$strategy.nft"
    grep -Fq "mangle iifname @interfaces meta mark 0 meta l4proto $protocol meta mark set 0x04000000" "$work/$strategy.nft"
  done
done

printf 'PASS: Dashboard server egress bypasses HAPP and full-tunnel interception with TLS/URLTest preserved\n'
