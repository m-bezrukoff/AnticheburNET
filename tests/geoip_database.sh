#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_dir="$root/anticheburnet/files/usr/share/anticheburnet/geoip"
helper="$root/anticheburnet/files/usr/bin/anticheburnet-geoip"
# Exercise the actual backend layout used to produce the APK and IPK packages.
awk '/^make_dir\(\)/{copy=1} /^build_app_root\(\)/{exit} copy{print}' "$root/build.sh" > "$work/layout.sh"
source "$work/layout.sh"
ROOT_DIR="$root"
RELEASE_VERSION=1.0.32
build_backend_root "$work/backend"
cmp "$source_dir/country.mmdb.gz" "$work/backend/usr/share/anticheburnet/geoip/country.mmdb.gz"
helper="$work/backend/usr/bin/anticheburnet-geoip"
test -x "$helper"
source_dir="$work/backend/usr/share/anticheburnet/geoip"
export ANTICHEBURNET_GEOIP_SOURCE="$source_dir" ANTICHEBURNET_GEOIP_STATE="$work/state"
database="$(sh "$helper")"
(cd "$(dirname "$database")" && sha256sum -c "$source_dir/country.sha256")
for ip in 8.8.8.8 2001:4860:4860::8888; do
    mmdblookup --file "$database" --ip "$ip" country iso_code | grep -Eq '"[A-Z]{2}"[[:space:]]+<utf8_string>'
done
# Warm lookups must not decompress the full database repeatedly.
mkdir "$work/bin"
printf '#!/bin/sh\nexit 99\n' > "$work/bin/gzip"
chmod +x "$work/bin/gzip"
warm="$(PATH="$work/bin:$PATH" sh "$helper")"
[ "$warm" = "$database" ]
# A corrupt replacement must be rejected before it touches the working cache.
mkdir "$work/corrupt"
printf 'invalid gzip' > "$work/corrupt/country.mmdb.gz"
printf '%064d  country.mmdb\n' 0 > "$work/corrupt/country.sha256"
if ANTICHEBURNET_GEOIP_SOURCE="$work/corrupt" sh "$helper" >/dev/null 2>&1; then
    echo 'Corrupt database was accepted' >&2; exit 1
fi
(cd "$(dirname "$database")" && sha256sum -c "$source_dir/country.sha256")
[ ! -e "$work/state/lock" ]
# Concurrent cold readers must publish the same verified generation.
export ANTICHEBURNET_GEOIP_STATE="$work/concurrent"
sh "$helper" > "$work/first" & first=$!
sh "$helper" > "$work/second" & second=$!
wait "$first"; wait "$second"
cmp "$work/first" "$work/second"
echo 'Bundled IPv4/IPv6 GeoIP database, integrity and cache checks passed'
