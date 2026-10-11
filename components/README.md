# Forkop Plus components

Target: OpenWrt 25.12, mediatek/filogic, aarch64_cortex-a53 (Redmi AX6000).
The component build and services are separate from the architecture-independent Forkop backend.

Build on Linux with Go 1.26.8 and the Filogic SDK pinned in `versions.env`:

```sh
bash build.sh 1.0.1 dist/filogic
bash components/build.sh 1.0.1 dist/filogic
```

The second command needs `qemu-user`, `iproute2`, `iputils-ping`, `openssl`, Python 3 and sudo
for isolated network tests. See `.github/workflows/filogic-build.yml` for all host dependencies.
The build also installs ucode for end-to-end importer tests and compares gzip, bzip2, xz,
zstd and SquashFS compression of the full official geodata. gzip is selected because
base OpenWrt can expand it without extra decoder packages or kernel modules. The helper
keeps the expanded files in `/var/run` (RAM), leaving only the archive on flash.
Go inputs use `go.sum`; the SDK and official Xray archive are checked against SHA256.
UPX 5.2.1 is pinned and verified too. It packs the three Go executables to fit the
AX6000 NAND budget; `upx -t` and all QEMU protocol tests run on the packed executables.
sing-box and AWG are built from the exact commits below. There are no hidden binary patches.

Corresponding upstream source and licenses:

- [sing-box extended source](https://github.com/shtorm-7/sing-box-extended/tree/5956780ba3f140feff771d003914a1b82ea9d5d0), GPL-3.0-or-later.
- [AmneziaWG Go 3.1 source](https://github.com/amnezia-vpn/amneziawg-go/tree/b5928efb6ca19f0153958460c3d141f04abc5c2e), MIT.
- [AmneziaWG tools 3.1 source](https://github.com/amnezia-vpn/amneziawg-tools/tree/ee0f0a9aa34ff0a0da4b3433b9512781cfe02843), GPL-2.0.
- [Xray 26.10.10 source](https://github.com/XTLS/Xray-core/tree/v26.10.10), MPL-2.0.

The extended snapshot retains its XHTTP implementation. Native Xray is a separate process
and uses a SOCKS bridge; sing-box does not embed Xray 26.10.10. AWG 3.1 is also a separate
official userspace daemon; it is not the more limited AWG endpoint embedded in extended.
This avoids relying on new AWG fields that the embedded endpoint does not expose.

Runtime tests launch the exact ARM64 binaries through QEMU. Hysteria 2 and Xray carry an HTTP
response to a local origin; AWG 3.1 performs a handshake and ICMP traffic between two network
namespaces with header protection, padding ranges, random trailers and disabled cookies.
These prove controlled protocol operation, not router throughput or every server option.

All six packages must use at most 35,000,000 file/allocated bytes in the build, leaving
5 MB within the requested 40 MB flash limit for metadata and generated configuration.
AmneziaWG is retained when the complete set fits this budget. `AdvancedSecurity=on` is
normalized by the importer: tools' legacy flag has no corresponding official Go 3.1
UAPI field, and that daemon always runs AWG. `off` is rejected explicitly.

Services and user configuration are documented in [the AX6000 guide](../docs/REDMI-AX6000.md).
