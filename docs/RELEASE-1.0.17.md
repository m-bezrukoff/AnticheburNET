# AnticheburNET 1.0.17

The complete installer now supports **mediatek/mt7622, aarch64_cortex-a53** on OpenWrt **25.12**, alongside mediatek/filogic. MT7622 devices no longer stop with the message that the complete suite requires Filogic.

Both targets use the same ARM64 userspace APKs. The release does not bundle target-specific kernel modules: `kmod-tun`, nftables modules and other dependencies come from the installed firmware's feeds. OpenWrt version, architecture, APK availability, checksums and available-space checks remain required.

Installer regression tests cover a complete six-package transaction on MT7622 with OpenWrt 25.12 and 25.12.3, and rejection of unsupported targets and mismatched architectures. Physical MT7622 router operation and throughput have not been tested in this release.

The release includes six APK packages, three generic application/LuCI/translation IPK packages, the updated installer and both checksum manifests. Application and LuCI packages are rebuilt for 1.0.17. Unchanged ARM64 cores are reused from the verified 1.0.16 release.

## Installation

Run this command over SSH as root on the router. The installer asks whether to install or uninstall, then asks for the interface language. Installation downloads the latest complete release, verifies SHA-256 checksums and preserves settings.

```sh
( f="$(mktemp /tmp/anticheburnet-install.XXXXXX)" || exit 1; trap 'rm -f "$f"' EXIT; wget -T 30 -O "$f" https://raw.githubusercontent.com/m-bezrukoff/AnticheburNET/main/install.sh && sh "$f" )
```
