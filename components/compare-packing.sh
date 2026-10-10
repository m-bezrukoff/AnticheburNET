#!/usr/bin/env bash
set -euo pipefail
work="$1"
output="$2"
data="$work/geodata"
mkdir -p "$data" "$work/packing"
cp "$work/xray/geoip.dat" "$work/xray/geosite.dat" "$data/"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$work/packing/geodata.tar" -C "$data" geoip.dat geosite.dat
gzip -9 -c "$work/packing/geodata.tar" > "$work/packing/geodata.tar.gz"
bzip2 -9 -c "$work/packing/geodata.tar" > "$work/packing/geodata.tar.bz2"
xz -9 -T2 -c "$work/packing/geodata.tar" > "$work/packing/geodata.tar.xz"
zstd -19 -T2 -q -c "$work/packing/geodata.tar" > "$work/packing/geodata.tar.zst"
mksquashfs "$data" "$work/packing/geodata.squashfs" -noappend -comp xz -processors 2 -no-progress >/dev/null
printf 'format,geodata_flash_bytes,router_requirement\n' > "$output/packing-comparison.csv"
for pair in 'raw:dat' 'gzip:tar.gz' 'bzip2:tar.bz2' 'xz:tar.xz' 'zstd:tar.zst' 'squashfs-xz:squashfs'; do
  format="${pair%%:*}"
  extension="${pair#*:}"
  case "$format" in
    raw) bytes=$(( $(stat -c%s "$data/geoip.dat") + $(stat -c%s "$data/geosite.dat") )); requirement='direct files' ;;
    gzip) bytes=$(stat -c%s "$work/packing/geodata.$extension"); requirement='BusyBox tar; expands in RAM' ;;
    bzip2) bytes=$(stat -c%s "$work/packing/geodata.$extension"); requirement='bzip2 decoder; expands in RAM' ;;
    xz) bytes=$(stat -c%s "$work/packing/geodata.$extension"); requirement='xz decoder; expands in RAM' ;;
    zstd) bytes=$(stat -c%s "$work/packing/geodata.$extension"); requirement='zstd decoder; expands in RAM' ;;
    *) bytes=$(stat -c%s "$work/packing/geodata.$extension"); requirement='loop and squashfs kernel support; read-only mount' ;;
  esac
  printf '%s,%s,%s\n' "$format" "$bytes" "$requirement" >> "$output/packing-comparison.csv"
done
cat "$output/packing-comparison.csv"
# gzip is available in base OpenWrt and retains every byte of official geodata.
cp "$work/packing/geodata.tar.gz" "$work/forkop-xray-root/usr/share/xray/"
(cd "$data"; sha256sum geoip.dat geosite.dat) > "$work/forkop-xray-root/usr/share/xray/geodata.sha256"
