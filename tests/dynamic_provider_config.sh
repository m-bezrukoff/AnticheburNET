#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/anticheburnet/files/usr/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/fixture.json" <<'JSON'
{"settings":{".name":"settings",".type":"settings","dns_server":"1.1.1.1"},"section":[{".name":"proxy",".type":"section","enabled":"1","action":"connection","selector_proxy_links":["socks5://user:old@127.0.0.1:8080"]}]}
JSON
ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture.json" "$work/current.json" 127.0.0.1 0 1 '' 1.14.1-extended-2.7.2-anticheburnet.3
node - "$work" <<'JS'
const fs = require('fs');
const work = process.argv[2];
const config = JSON.parse(fs.readFileSync(`${work}/current.json`));
if (config.outbounds.length || config.providers[0].type !== 'anticheburnet') throw Error('subscriptions must be delegated to the managed provider');
const path = config.providers[0].path;
const payload = JSON.parse(fs.readFileSync(path));
if (!payload.outbounds.some(node => node.password === 'old') || !payload.outbounds.some(node => node.tag === 'proxy-out')) throw Error('proxy and selector must be in the provider');
if ((fs.statSync(path).mode & 0o777) !== 0o600) throw Error('provider credentials must be private');
const fixture = JSON.parse(fs.readFileSync(`${work}/fixture.json`));
fixture.section[0].selector_proxy_links = ['socks5://user:new@127.0.0.1:8081'];
fs.writeFileSync(`${work}/fixture.json`, JSON.stringify(fixture));
JS
ucode -L "$lib" "$lib/singbox/generator.uc" generate-config-fixture "$work/fixture.json" "$work/candidate.json" 127.0.0.1 0 1 '' 1.14.1-extended-2.7.2-anticheburnet.3
ucode -L "$lib" "$lib/singbox/runtime.uc" provider-update-compatible-fixture "$work/current.json" "$work/candidate.json" "$work/current.json.awg.json" "$work/candidate.json.awg.json"
node - "$work/candidate.json.providers.json" <<'JS'
const fs = require('fs');
const path = process.argv[2];
const payload = JSON.parse(fs.readFileSync(path));
payload.configuration.route.final = 'changed-routing';
fs.writeFileSync(path, JSON.stringify(payload));
JS
if ucode -L "$lib" "$lib/singbox/runtime.uc" provider-update-compatible-fixture "$work/current.json" "$work/candidate.json" "$work/current.json.awg.json" "$work/candidate.json.awg.json"; then
  echo 'FAIL: topology changes must require Apply without an automatic service restart' >&2
  exit 1
fi
printf 'dynamic provider generation and compatibility checks passed\n'
