#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export FORKOP_LIB="$root/forkop/files/usr/lib"
uc() { ucode -L "$FORKOP_LIB" "$@"; }
xray="$root/components/xray/files/usr/lib/forkop-components/xray.uc"
awg="$root/components/awg/files/usr/lib/forkop-components/awg.uc"
cat > "$work/native.json" <<'JSON'
{"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-4000-8000-000000000001","encryption":"none"}]}]},"streamSettings":{"network":"xhttp","xhttpSettings":{"mode":"auto","extra":{"scMaxEachPostBytes":1000000}},"sockopt":{"tcpFastOpen":true}}}]}
JSON
uc "$xray" prepare "$work/native.json" "$work/prepared.json"
uc -e '
let fs=require("fs"); let c=json(fs.readfile(ARGV[0]));
if(c.inbounds[0].listen!="127.0.0.1" || c.inbounds[0].port!=10810 || !c.inbounds[0].settings.udp) die("SOCKS ingress failure");
if(c.outbounds[0].streamSettings.sockopt.mark!=134217728 || !c.outbounds[0].streamSettings.sockopt.tcpFastOpen) die("mark or sockopt failure");
if(c.outbounds[0].streamSettings.xhttpSettings.extra.scMaxEachPostBytes!=1000000) die("native Xray options were lost");
' "$work/prepared.json"
cat > "$work/awg.conf" <<'CONF'
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.7.0.2/32, fd00:7::2/128
MTU = 1376
DNS = 1.1.1.1
Jc = 6
I1 = <b 0x01020304>
H1 = 1-100
HeaderProtectionKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
ContentPaddingAddition = 10-20
RandomTrailers = on
DisableCookies = on
[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = example.com:443
PersistentKeepalive = 20-30
AdvancedSecurity = on
CONF
uc "$awg" prepare "$work/awg.conf" "$work/device.conf" > "$work/state.json"
grep -Fqx 'RandomTrailers = on' "$work/device.conf"
grep -Fqx 'DisableCookies = on' "$work/device.conf"
grep -Fqx 'HeaderProtectionKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' "$work/device.conf"
grep -Fqx 'PersistentKeepalive = 20-30' "$work/device.conf"
grep -Fqx 'AdvancedSecurity = on' "$work/device.conf"
grep -Fqx 'FwMark = 134217728' "$work/device.conf"
if grep -Eq '^(Address|MTU|DNS) =' "$work/device.conf"; then exit 1; fi
uc -e 'let fs=require("fs"); let c=json(fs.readfile(ARGV[0])); if(length(c.addresses)!=2 || c.mtu!=1376) die("AWG network metadata lost");' "$work/state.json"
cat >> "$work/awg.conf" <<'CONF'
[Peer]
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
AllowedIPs = 192.0.2.0/24
CONF
uc "$awg" prepare "$work/awg.conf" "$work/device.conf" > "$work/state.json"
[ "$(grep -c '^\[Peer\]$' "$work/device.conf")" = 2 ]
printf '\nPreUp = touch /tmp/unsafe\n' >> "$work/awg.conf"
if uc "$awg" prepare "$work/awg.conf" "$work/unsafe.conf" 2>/dev/null; then
  echo 'AWG quick hook was accepted' >&2; exit 1
fi
printf '{"outbounds":[]}\n' > "$work/invalid.json"
if uc "$xray" prepare "$work/invalid.json" 2>/dev/null; then exit 1; fi
printf 'Fork component configuration tests passed\n'
