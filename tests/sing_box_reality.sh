#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FORKOP_LIB="$root/forkop/files/usr/lib"
parser="$FORKOP_LIB/subscription/parser.uc"
generator="$FORKOP_LIB/singbox/generator.uc"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export TMP_SUBSCRIPTION_FOLDER="$work/subscriptions"
export FORKOP_PERSISTENT_SUBSCRIPTION_CACHE_DIR="$work/persistent"
mkdir -p "$TMP_SUBSCRIPTION_FOLDER" "$FORKOP_PERSISTENT_SUBSCRIPTION_CACHE_DIR"

link='vless://00000000-0000-4000-8000-000000000001@example.com:443?security=reality&sni=example.com&pbk=jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0&sid=0123456789abcdef#uri'
printf '%s\n' "$link" > "$work/uri.txt"
ucode -L "$FORKOP_LIB" "$parser" normalize-uri-list "$work/uri.txt" "$work/uri.json"
cat > "$work/clash.yaml" <<'YAML'
proxies:
  - name: clash
    type: vless
    server: example.com
    port: 443
    uuid: 00000000-0000-4000-8000-000000000001
    tls: true
    client-fingerprint: firefox
    reality-opts:
      public-key: jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0
      short-id: 0123456789abcdef
YAML
ucode -L "$FORKOP_LIB" "$parser" normalize-clash-yaml "$work/clash.yaml" "$work/clash.json"
cat > "$work/xray-input.json" <<'JSON'
{"outbounds":[{"tag":"xray","protocol":"vless","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-4000-8000-000000000001","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"example.com","fingerprint":"edge","publicKey":"jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0","shortId":"0123456789abcdef"}}}]}
JSON
ucode -L "$FORKOP_LIB" "$parser" normalize-content "$work/xray-input.json" "$work/xray.json"
cat > "$work/json-input.json" <<'JSON'
{"outbounds":[{"tag":"native-json","type":"vless","server":"example.com","server_port":443,"uuid":"00000000-0000-4000-8000-000000000001","tls":{"enabled":true,"server_name":"example.com","reality":{"enabled":true,"public_key":"jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0","short_id":"0123456789abcdef"}}}]}
JSON
ucode -L "$FORKOP_LIB" "$parser" normalize-content "$work/json-input.json" "$work/native.json"
# An already cached subscription must receive the fix without a download.
cp "$work/uri.json" "$TMP_SUBSCRIPTION_FOLDER/cached-subscription-1.json"
printf '%s' 'https://example.com/reality' > "$TMP_SUBSCRIPTION_FOLDER/cached-subscription-1.url"

cat > "$work/fixture.uc" <<'UCODE'
let fs = require("fs");
let work = ARGV[0];
let sections = [];
for (let source in ["uri", "clash", "xray", "native"]) {
    let imported = json(fs.readfile(work + "/" + source + ".json"));
    if (length(imported.outbounds) != 1)
        die("REALITY import fixture did not produce one outbound: " + source);
    push(sections, {
        ".name": source, ".type": "section", enabled: "1", action: "connection",
        outbound_jsons: [sprintf("%J", imported.outbounds[0])]
    });
}
push(sections, {
    ".name": "manual", ".type": "section", enabled: "1", action: "connection",
    selector_proxy_links: [trim(fs.readfile(work + "/uri.txt"))]
});
push(sections, {
    ".name": "cached", ".type": "section", enabled: "1", action: "connection",
    subscription_urls: ["https://example.com/reality"]
});
let classical = json(fs.readfile(work + "/native.json")).outbounds[0];
classical.tag = "classical";
classical.tls.reality.support_x25519mlkem768 = false;
classical.tls.utls = { enabled: true, fingerprint: "firefox" };
let plain = json(sprintf("%J", classical));
plain.tag = "plain-tls";
delete plain.tls.reality;
let disabled = json(sprintf("%J", classical));
disabled.tag = "disabled-reality";
disabled.tls.reality.enabled = false;
delete disabled.tls.reality.support_x25519mlkem768;
push(sections, {
    ".name": "explicit", ".type": "section", enabled: "1", action: "connection",
    outbound_jsons: [sprintf("%J", classical), sprintf("%J", plain), sprintf("%J", disabled)]
});
fs.writefile(work + "/fixture.json", sprintf("%J", {
    settings: { ".name": "settings", ".type": "settings", dns_server: "1.1.1.1", service_listen_address: "127.0.0.1" },
    section: sections
}));
UCODE
ucode -L "$FORKOP_LIB" "$work/fixture.uc" "$work"
for entry in extended:1.14.1-extended-2.7.2-forkop.1 stable:1.14.1 old:1.14.0-extended-2.7.1 unknown:; do
    name="${entry%%:*}"
    version="${entry#*:}"
    mkdir -p "$work/$name.json.section-cache" "$work/$name.json.rulesets"
    ucode -L "$FORKOP_LIB" "$generator" generate-config-fixture \
        "$work/fixture.json" "$work/$name.json" 127.0.0.1 0 1 '' "$version"
done
cat > "$work/assert.uc" <<'UCODE'
let fs = require("fs");
let reality = require("singbox.reality");
let work = ARGV[0];
function check(ok, message) { if (!ok) die(message + "\n"); }
check(reality.supports_hybrid_share("1.14.1-extended-2.7.2-forkop.1"), "pinned core supported");
check(reality.supports_hybrid_share("1.15.0-extended-2.8.0"), "newer extended supported");
for (let name in ["extended", "stable", "old", "unknown"]) {
    let config = json(fs.readfile(work + "/" + name + ".json"));
    let count = 0;
    for (let outbound in config.outbounds) {
        let tls = outbound.tls;
        if (outbound.tag == "plain-tls" || outbound.tag == "disabled-reality") {
            check(tls.utls.fingerprint == "firefox", "unrelated TLS fingerprint preserved");
            check(tls.reality == null || tls.reality.support_x25519mlkem768 == null, "disabled REALITY left unchanged");
            continue;
        }
        if (type(tls) != "object" || type(tls.reality) != "object") continue;
        if (outbound.tag == "classical") {
            check(tls.reality.support_x25519mlkem768 === false, "explicit false preserved");
            check(tls.utls.fingerprint == "firefox", "classical fingerprint preserved");
            continue;
        }
        count++;
        check(tls.reality.public_key == "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0", "public key preserved");
        check(tls.reality.short_id == "0123456789abcdef", "short id preserved");
        check(tls.server_name == "example.com", "SNI preserved");
        if (name == "extended") {
            check(tls.reality.support_x25519mlkem768 === true, "hybrid share enabled for " + outbound.tag);
            check(tls.utls.enabled === true && tls.utls.fingerprint == "chrome", "compatible fingerprint for " + outbound.tag);
        } else {
            check(tls.reality.support_x25519mlkem768 == null, "extended field must not leak into unsupported core");
        }
    }
    check(count == 6, "all six REALITY sources must reach generation: " + name);
}
let cached = json(fs.readfile(work + "/subscriptions/cached-subscription-1.json"));
check(cached.outbounds[0].tls.reality.support_x25519mlkem768 == null, "generation must not mutate subscription cache");
print("REALITY generation compatibility checks passed\n");
UCODE
ucode -L "$FORKOP_LIB" "$work/assert.uc" "$work"
