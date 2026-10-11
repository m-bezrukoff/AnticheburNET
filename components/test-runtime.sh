#!/usr/bin/env bash
# Exercise the exact ARM64 artifacts, including encrypted Hysteria 2 traffic.
set -euo pipefail
umask 077
work="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANTICHEBURNET_LIB="$root/anticheburnet/files/usr/lib"
test_dir="$(mktemp -d)"
pids=()
namespaces=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  for ns in "${namespaces[@]}"; do ip netns del "$ns" 2>/dev/null || true; done
  rm -rf "$test_dir"
}
trap cleanup EXIT
qemu-aarch64 "$work/test-socket-mark.arm64"
printf 'anticheburnet-arm64-runtime-ok\n' > "$test_dir/probe.txt"
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$test_dir" > "$test_dir/http.log" 2>&1 &
pids+=("$!")
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
  -keyout "$test_dir/key.pem" -out "$test_dir/cert.pem" >/dev/null 2>&1
cat > "$test_dir/hy-server.json" <<JSON
{"inbounds":[{"type":"hysteria2","listen":"127.0.0.1","listen_port":18443,"users":[{"password":"local-runtime-test"}],"tls":{"enabled":true,"certificate_path":"$test_dir/cert.pem","key_path":"$test_dir/key.pem"}}],"outbounds":[{"type":"direct"}]}
JSON
cat > "$test_dir/hy-client.json" <<'JSON'
{"inbounds":[{"type":"socks","listen":"127.0.0.1","listen_port":10820}],"outbounds":[{"type":"hysteria2","server":"127.0.0.1","server_port":18443,"password":"local-runtime-test","tls":{"enabled":true,"server_name":"localhost","insecure":true}}]}
JSON
cat > "$test_dir/xray-native.json" <<'JSON'
{"outbounds":[{"tag":"direct","protocol":"freedom"}],"routing":{"rules":[{"type":"field","domain":["geosite:cn"],"outboundTag":"direct"},{"type":"field","ip":["geoip:private"],"outboundTag":"direct"}]}}
JSON
ucode -L "$ANTICHEBURNET_LIB" "$root/components/xray/files/usr/lib/anticheburnet-components/xray.uc" prepare "$test_dir/xray-native.json" "$test_dir/xray.json"
export ANTICHEBURNET_XRAY_ASSET_SOURCE="$work/anticheburnet-xray-root/usr/share/xray"
export ANTICHEBURNET_XRAY_ASSET_STATE="$test_dir/xray-cache"
XRAY_LOCATION_ASSET=$(sh "$root/components/xray/files/usr/bin/anticheburnet-xray-assets")
export XRAY_LOCATION_ASSET
# Exercise the converter on complete, real DAT files, including IPv4 and IPv6.
ucode -L "$ANTICHEBURNET_LIB" -e '
let g=require("routing.geodata"),fs=require("fs"),ip=require("core.ip");
let networks=g.convert(fs.readfile(ARGV[0]),"geoip","ru").ip_cidr;
if(length(networks)<100)die("Full GeoIP RU entry was not read\n");
for(let prefix in networks)if(!ip.valid_ip_cidr(prefix))die("Invalid converted GeoIP prefix\n");
let domains=g.convert(fs.readfile(ARGV[1]),"geosite","cn");
let count=0;for(let key,values in domains)count+=length(values);
if(count<100)die("Full GeoSite entry was not read\n");
print("Full DAT GeoIP/GeoSite conversion passed\n");
' "$XRAY_LOCATION_ASSET/geoip.dat" "$XRAY_LOCATION_ASSET/geosite.dat"
# A second invocation must reuse the verified RAM cache.
[[ "$(sh "$root/components/xray/files/usr/bin/anticheburnet-xray-assets")" == "$XRAY_LOCATION_ASSET" ]]
qemu-aarch64 "$work/xray/xray" run -test -config "$test_dir/xray.json"
qemu-aarch64 "$work/xray/xray" run -config "$test_dir/xray.json" > "$test_dir/xray.log" 2>&1 &
pids+=("$!")
for role in server client; do
  qemu-aarch64 "$work/sing-box.arm64" check -c "$test_dir/hy-$role.json"
  qemu-aarch64 "$work/sing-box.arm64" run -c "$test_dir/hy-$role.json" > "$test_dir/hy-$role.log" 2>&1 &
  pids+=("$!")
done
for port in 10810 10820; do
  success=0
  for attempt in {1..20}; do
    if curl --noproxy '' -fsS --max-time 8 --socks5-hostname "127.0.0.1:$port" \
      http://127.0.0.1:18080/probe.txt > "$test_dir/response" && \
      cmp "$test_dir/probe.txt" "$test_dir/response"; then success=1; break; fi
    sleep 1
  done
  if [[ "$success" != 1 ]]; then cat "$test_dir/"*.log; exit 1; fi
done
echo 'ARM64 native Xray SOCKS and encrypted Hysteria 2 round trips passed'

# Two isolated networks ensure the ping actually crosses encrypted AWG 3.1 peers.
ns1="fawg1-$$"
ns2="fawg2-$$"
for ns in "$ns1" "$ns2"; do ip netns add "$ns"; namespaces+=("$ns"); done
ip link add fa-veth1 type veth peer name fa-veth2
ip link set fa-veth1 netns "$ns1"
ip link set fa-veth2 netns "$ns2"
for index in 1 2; do
  ns_var="ns$index"
  ns="${!ns_var}"
  ip -n "$ns" link set lo up
  ip -n "$ns" address add "192.0.2.$index/24" dev "fa-veth$index"
  ip -n "$ns" link set "fa-veth$index" up
  ip netns exec "$ns" qemu-aarch64 "$work/amneziawg-go.arm64" -f "fawg$index" > "$test_dir/awg$index.log" 2>&1 &
  pids+=("$!")
  qemu-aarch64 "$work/awg-tools/src/wg" genkey > "$test_dir/private$index"
  qemu-aarch64 "$work/awg-tools/src/wg" pubkey < "$test_dir/private$index" > "$test_dir/public$index"
done
qemu-aarch64 "$work/awg-tools/src/wg" genkey > "$test_dir/header-key"
for index in 1 2; do
  ns_var="ns$index"
  ns="${!ns_var}"
  peer=$((3 - index))
  for attempt in {1..50}; do
    [[ ! -S "/var/run/amneziawg/fawg$index.sock" ]] || break
    sleep 0.1
  done
  cat > "$test_dir/awg$index.conf" <<CONF
[Interface]
PrivateKey = $(cat "$test_dir/private$index")
Address = 10.201.0.$index/32
ListenPort = 18444
Jc = 2
Jmin = 32
Jmax = 64
S1 = 16
S2 = 16
S3 = 16
S4 = 16
H1 = 101-110
H2 = 201-210
H3 = 301-310
H4 = 401-410
HeaderProtectionKey = $(cat "$test_dir/header-key")
ContentPaddingAddition = 10-20
RandomTrailers = on
DisableCookies = on
[Peer]
PublicKey = $(cat "$test_dir/public$peer")
AllowedIPs = 10.201.0.$peer/32
Endpoint = 192.0.2.$peer:18444
PersistentKeepalive = 20-30
AdvancedSecurity = on
CONF
  # Fetch the profile through the production URL importer before applying it to
  # the real official ARM64 AWG tools and performing an encrypted handshake.
  mkdir -p "$test_dir/bin"
  cat > "$test_dir/bin/awg" <<SH
#!/bin/sh
exec qemu-aarch64 "$work/awg-tools/src/wg" "\$@"
SH
  chmod 755 "$test_dir/bin/awg"
  ANTICHEBURNET_COMPONENT_LIB="$root/components/awg/files/usr/lib" PATH="$test_dir/bin:$PATH" \
    sh "$root/components/awg/files/usr/bin/anticheburnet-awg-import" --output "$test_dir/imported$index.conf" \
    "http://127.0.0.1:18080/awg$index.conf"
  cmp "$test_dir/awg$index.conf" "$test_dir/imported$index.conf"
  # A non-AWG response must not replace the saved, working profile.
  if ANTICHEBURNET_COMPONENT_LIB="$root/components/awg/files/usr/lib" PATH="$test_dir/bin:$PATH" \
    sh "$root/components/awg/files/usr/bin/anticheburnet-awg-import" --output "$test_dir/imported$index.conf" \
    http://127.0.0.1:18080/probe.txt; then exit 1; fi
  cmp "$test_dir/awg$index.conf" "$test_dir/imported$index.conf"
  ucode -L "$ANTICHEBURNET_LIB" "$root/components/awg/files/usr/lib/anticheburnet-components/awg.uc" prepare \
    "$test_dir/imported$index.conf" "$test_dir/device$index.conf" > "$test_dir/state$index.json"
  if ! ip netns exec "$ns" qemu-aarch64 "$work/awg-tools/src/wg" setconf "fawg$index" "$test_dir/device$index.conf"; then
    cat "$test_dir/awg$index.log"; exit 1
  fi
  [[ "$(ip netns exec "$ns" qemu-aarch64 "$work/awg-tools/src/wg" show "fawg$index" fwmark)" == 0x8000000 ]]
  ip -n "$ns" address add "10.201.0.$index/32" dev "fawg$index"
  ip -n "$ns" link set "fawg$index" mtu 1376 up
  ip -n "$ns" route add "10.201.0.$peer/32" dev "fawg$index"
done
ip netns exec "$ns1" ping -c 3 -W 10 10.201.0.2 || { cat "$test_dir/awg"*.log; exit 1; }
ip netns exec "$ns1" qemu-aarch64 "$work/awg-tools/src/wg" show fawg1 latest-handshakes | \
  awk '{ if ($2 > 0) ok=1 } END { exit !ok }'
echo 'ARM64 AmneziaWG 3.1 encrypted handshake and tunnel traffic passed'
