#!/usr/bin/env bash
set -euo pipefail
component_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-1.0.0}"
output="${2:-$component_root/dist/filogic}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
# shellcheck source=components/versions.env
source "$component_root/components/versions.env"
# Reuse the existing SDK download, package metadata and conffile implementation.
# shellcheck source=build.sh
source "$component_root/build.sh" "$version" "$output"
output="$OUTPUT_DIR"
mkdir -p "$output" "$BUILD_DIR/components" "$SDK_CACHE_DIR"
work="$BUILD_DIR/components"
sdk_archive="$(download_sdk_archive "$FILOGIC_SDK_URL")"
printf '%s  %s\n' "$FILOGIC_SDK_SHA256" "$sdk_archive" | sha256sum -c -
sdk="$(extract_sdk filogic "$sdk_archive" "$FILOGIC_SDK_URL")"
apk_bin="$sdk/staging_dir/host/bin/apk"
cc="$(find "$sdk/staging_dir" -path '*/bin/aarch64-openwrt-linux-musl-gcc' -print -quit)"
[[ -x "$cc" && -x "$apk_bin" ]] || { echo 'Filogic SDK tools missing' >&2; exit 1; }
export STAGING_DIR="$sdk/staging_dir"
export PATH="$(dirname "$cc"):$PATH"

checkout_pinned() {
  local name="$1" repository="$2" revision="$3"
  local destination="$work/$name"
  if [[ ! -d "$destination/.git" ]]; then
    git init "$destination"
    git -C "$destination" remote add origin "https://github.com/$repository.git"
  fi
  git -C "$destination" fetch --depth 1 origin "$revision"
  git -C "$destination" checkout --detach FETCH_HEAD
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]
}
checkout_pinned sing-box shtorm-7/sing-box-extended "$SING_BOX_COMMIT"
checkout_pinned awg-go amnezia-vpn/amneziawg-go "$AWG_GO_COMMIT"
checkout_pinned awg-tools amnezia-vpn/amneziawg-tools "$AWG_TOOLS_COMMIT"

tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
bash "$component_root/components/prepare-utls.sh" "$work/sing-box" "$work"
python3 "$component_root/components/prepare-providers.py" "$work/sing-box"
(
  cd "$work/sing-box"
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -modfile="$work/sing-box.mod" -trimpath -tags "$tags" \
    -ldflags "-s -w -X github.com/sagernet/sing-box/constant.Version=$SING_BOX_VERSION" \
    -o "$work/sing-box.arm64" ./cmd/sing-box
)
(
  cd "$work/awg-go"
  # Upstream's Makefile generates this file from git tags; a SHA checkout has no tags.
  printf 'package main\n\nconst Version = "%s"\n' "$AWG_GO_VERSION" > version.go
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags '-s -w' -o "$work/amneziawg-go.arm64" .
)
make -C "$work/awg-tools/src" -j2 CC="$cc" LDFLAGS=-static WITH_WGQUICK=no WITH_SYSTEMDUNITS=no
"$cc" -static -Wall -Wextra -Werror "$component_root/components/test-socket-mark.c" -o "$work/test-socket-mark.arm64"
curl -fL --retry 3 "https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-arm64-v8a.zip" -o "$work/xray.zip"
printf '%s  %s\n' "$XRAY_ARM64_SHA256" "$work/xray.zip" | sha256sum -c -
unzip -oq "$work/xray.zip" xray geoip.dat geosite.dat -d "$work/xray"

# AX6000 has 128 MB NAND. Pack executables without removing protocols or geodata.
curl -fL --retry 3 "https://github.com/upx/upx/releases/download/v$UPX_VERSION/upx-$UPX_VERSION-amd64_linux.tar.xz" -o "$work/upx.tar.xz"
printf '%s  %s\n' "$UPX_AMD64_SHA256" "$work/upx.tar.xz" | sha256sum -c -
tar -xJf "$work/upx.tar.xz" -C "$work"
upx="$work/upx-$UPX_VERSION-amd64_linux/upx"
chmod 755 "$work/xray/xray"
"$upx" --best --lzma "$work/sing-box.arm64" "$work/amneziawg-go.arm64" "$work/xray/xray"
"$upx" -t "$work/sing-box.arm64" "$work/amneziawg-go.arm64" "$work/xray/xray"
: > "$output/installed-sizes.txt"

package_component() {
  local name="$1" package_version="$2" description="$3" depends="$4" license="$5" conffile="${6:-}"
  local package_root="$work/$name-root"
  local service="$name"
  case "$name" in sing-box-extended) service=sing-box ;; anticheburnet-amneziawg) service=anticheburnet-awg ;; esac
  local scripts="$work/$name-scripts"
  mkdir -p "$scripts"
  printf '#!/bin/sh\nservice=%s\n' "$service" > "$scripts/post.sh"
  cat >> "$scripts/post.sh" <<'SH'
[ "${IPKG_NO_SCRIPT:-}" != 1 ] || exit 0
[ -z "${IPKG_INSTROOT:-}" ] || exit 0
# AnticheburNET regenerates engine configs and temporary Happ rule sets before
# starting the suite, after APK has released its database lock.
[ "${ANTICHEBURNET_DEFER_PACKAGE_RESTART:-}" != 1 ] || exit 0
"/etc/init.d/$service" enable
"/etc/init.d/$service" restart || true
SH
  printf '#!/bin/sh\nservice=%s\n' "$service" > "$scripts/pre.sh"
  cat >> "$scripts/pre.sh" <<'SH'
[ "${IPKG_NO_SCRIPT:-}" != 1 ] || exit 0
[ -z "${IPKG_INSTROOT:-}" ] || exit 0
"/etc/init.d/$service" stop || true
[ "$service" != anticheburnet-awg ] || /etc/init.d/anticheburnet-awg-subscriptions stop || true
SH
  chmod 755 "$scripts/"*.sh
  local asset_name="${name}_${package_version}_aarch64_cortex-a53.apk"
  [[ "$name" != sing-box-extended ]] || asset_name="${name}_${SING_BOX_VERSION}_openwrt_aarch64_cortex-a53.apk"
  generate_apk_metadata_files "$name" "$package_root" "$conffile"
  printf '%s: %s bytes\n' "$name" "$(du -sb "$package_root" | cut -f1)" >> "$output/installed-sizes.txt"
  unshare -r sh -c 'chown -R 0:0 "$1"; shift; exec "$@"' sh "$package_root" \
    "$apk_bin" mkpkg --files "$package_root" --output "$output/$asset_name" \
    -I "name:$name" -I "version:$package_version" -I "description:$description" \
    -I arch:aarch64_cortex-a53 -I "license:$license" -I origin:anticheburnet \
    -I 'maintainer:Max Bezrukov <73909358+m-bezrukoff@users.noreply.github.com>' \
    -I url:https://github.com/m-bezrukoff/AnticheburNET -I "depends:$depends" \
    -s "post-install:$scripts/post.sh" -s "post-upgrade:$scripts/post.sh" \
    -s "pre-upgrade:$scripts/pre.sh" -s "pre-deinstall:$scripts/pre.sh"
}

sb_root="$work/sing-box-extended-root"
mkdir -p "$sb_root/usr/bin" "$sb_root/etc/init.d" "$sb_root/etc/config"
install -m755 "$work/sing-box.arm64" "$sb_root/usr/bin/sing-box"
cp "$component_root/components/sing-box/files/etc/init.d/sing-box" "$sb_root/etc/init.d/sing-box"
cp "$component_root/components/sing-box/files/etc/config/sing-box" "$sb_root/etc/config/sing-box"
chmod 755 "$sb_root/etc/init.d/sing-box"
mkdir -p "$sb_root/usr/share/licenses/sing-box-extended"
install -m644 "$work/sing-box/LICENSE" "$sb_root/usr/share/licenses/sing-box-extended/LICENSE"
package_component sing-box-extended 1.14.1-r4 'AnticheburNET extended sing-box with Hysteria 2 and XHTTP' \
  'ca-bundle kmod-tun !sing-box !sing-box-tiny' GPL-3.0-or-later /etc/config/sing-box

for kind in xray awg; do
  case "$kind" in xray) name=anticheburnet-xray ;; awg) name=anticheburnet-amneziawg ;; esac
  mkdir -p "$work/$name-root"
  cp -a "$component_root/components/$kind/files/." "$work/$name-root/"
  mkdir -p "$work/$name-root/etc/anticheburnet"
  chmod 700 "$work/$name-root/etc/anticheburnet"
  chmod 755 "$work/$name-root/usr/bin/"* "$work/$name-root/etc/init.d/"*
done
install -m755 "$work/xray/xray" "$work/anticheburnet-xray-root/usr/bin/xray"
mkdir -p "$work/anticheburnet-xray-root/usr/share/xray"
rm -f "$work/anticheburnet-xray-root/usr/share/xray/geoip.dat" "$work/anticheburnet-xray-root/usr/share/xray/geosite.dat"
bash "$component_root/components/compare-packing.sh" "$work" "$output"
mkdir -p "$work/anticheburnet-xray-root/usr/share/licenses/anticheburnet-xray"
curl -fL --retry 3 "https://raw.githubusercontent.com/XTLS/Xray-core/v$XRAY_VERSION/LICENSE" \
  -o "$work/anticheburnet-xray-root/usr/share/licenses/anticheburnet-xray/LICENSE"
package_component anticheburnet-xray 26.10.10-r1 'Native Xray 26.10.10 SOCKS bridge for AnticheburNET' \
  'anticheburnet ca-bundle !xray-core' MPL-2.0 /etc/config/anticheburnet_xray
install -m755 "$work/amneziawg-go.arm64" "$work/anticheburnet-amneziawg-root/usr/bin/amneziawg-go"
install -m755 "$work/awg-tools/src/wg" "$work/anticheburnet-amneziawg-root/usr/bin/awg"
mkdir -p "$work/anticheburnet-amneziawg-root/usr/share/licenses/anticheburnet-amneziawg"
install -m644 "$work/awg-go/LICENSE" "$work/anticheburnet-amneziawg-root/usr/share/licenses/anticheburnet-amneziawg/daemon-MIT"
install -m644 "$work/awg-tools/COPYING" "$work/anticheburnet-amneziawg-root/usr/share/licenses/anticheburnet-amneziawg/tools-GPL-2.0"
package_component anticheburnet-amneziawg 3.1.20260828-r5 'Official AmneziaWG 3.1 userspace client with subscription import' \
  'anticheburnet kmod-tun ip-full' 'MIT AND GPL-2.0' /etc/config/anticheburnet_awg

# Inspect the exact ARM binaries on the build host through qemu-user.
qemu-aarch64 "$sb_root/usr/bin/sing-box" version
qemu-aarch64 "$work/anticheburnet-xray-root/usr/bin/xray" version
qemu-aarch64 "$work/anticheburnet-amneziawg-root/usr/bin/amneziawg-go" --version
qemu-aarch64 "$work/anticheburnet-amneziawg-root/usr/bin/awg" --version
for package in "$output/"*_aarch64_cortex-a53.apk; do
  "$apk_bin" adbdump "$package" > "$work/package-metadata.txt"
  head -60 "$work/package-metadata.txt"
done
# Count every installed file from all six packages, not their compressed APK size.
total=0
allocated=0
for package in "$output/"*.apk; do
  "$apk_bin" adbdump "$package" > "$work/size-metadata.txt"
  bytes=$(awk '$1 == "installed-size:" { print $2; exit }' "$work/size-metadata.txt")
  [[ "$bytes" =~ ^[0-9]+$ ]] || { echo "Missing installed size: $package" >&2; exit 1; }
  entries=$(awk '/^ *- name:/ { count++ } END { print count+1 }' "$work/size-metadata.txt")
  # At most one extra 4 KiB block per metadata/file/directory entry.
  blocks=$((bytes + entries * 4096))
  total=$((total + bytes))
  allocated=$((allocated + blocks))
done
printf 'All six packages: %s file bytes; at most %s bytes including 4 KiB entry overhead\n' "$total" "$allocated" >> "$output/installed-sizes.txt"
cat "$output/installed-sizes.txt"
# Leave 5 MB for package database, generated configuration and filesystem overhead.
(( total <= 35000000 && allocated <= 35000000 )) || { echo '40 MB flash budget exceeded (including reserve)' >&2; exit 1; }
cp "$component_root/components/versions.env" "$output/versions.env"
(
  cd "$output"
  sha256sum ./*.apk > SHA256SUMS
)
sudo bash "$component_root/components/test-runtime.sh" "$work"
sudo bash "$component_root/components/test-happ-runtime.sh" "$work"
