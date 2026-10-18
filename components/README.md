# AnticheburNET components

AnticheburNET is intended for all devices running OpenWrt 25.12. Supported protocols include VLESS, Hysteria 2, XHTTP and AmneziaWG 3.1, with support for the full Xray 26.10.10 core. Current prebuilt components support mediatek/filogic and mediatek/mt7622 with aarch64_cortex-a53.
The component build and services are separate from the architecture-independent AnticheburNET backend.
Both targets use the same ARM64 userspace APKs. Go executables use `CGO_ENABLED=0`,
and AmneziaWG tools are statically linked. No target-specific kernel modules are
bundled; kernel dependencies come from the installed firmware's feeds.

For installation on the router, run the single SSH command in
[the OpenWrt 25.12 guide](../docs/OPENWRT-25.12.md#установка). It downloads all six release APKs
from GitHub, verifies their SHA-256 checksums and installs the complete suite.
The commands below are for building packages on a Linux development host.

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
component size budget; `upx -t` and all QEMU protocol tests run on the packed executables.
sing-box and AWG are built from the exact commits below. The sing-box build applies
the reviewed source patch `patches/utls-modern-browser-presets.patch` to a private
copy of metacubex/uTLS 1.8.7; the Go module cache remains unchanged. Firefox 148,
Safari 26.3 and Firefox hybrid/classical key reuse are backported from
[the uTLS revision used by Xray 26.10.10](https://github.com/refraction-networking/utls/tree/aa6edf4b11af).
Subscription fingerprints remain unchanged. The patch updates the browser presets
behind `firefox` and `safari`, so their REALITY handshakes include X25519MLKEM768.
The source build tests the actual generated key shares before compiling the core.

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

All six packages must use at most 35,000,000 file/allocated bytes in the build.
AmneziaWG is retained when the complete set fits this budget. `AdvancedSecurity=on` is
normalized by the importer: tools' legacy flag has no corresponding official Go 3.1
UAPI field, and that daemon always runs AWG. `off` is rejected explicitly.

Services and user configuration are documented in [the OpenWrt 25.12 guide](../docs/OPENWRT-25.12.md).

## Dynamic subscription providers

Component `sing-box-extended` 1.14.1-r4 (`anticheburnet.4`) includes the managed
provider installed by `prepare-providers.py`. Build this component together with
the backend; older component APKs do not implement its atomic update API.
After installing both, Apply configuration once to migrate an existing flat
configuration. Subsequent subscription updates leave sing-box, DNS failover,
Priority, inbounds and firewall services running.

The backend writes a private provider file and explicitly updates it through
`PUT /providers/proxies/anticheburnet-subscriptions`. It checks the returned live
revision before publishing dashboard metadata. Constructors, dependencies and
startup are validated in isolation; a rejected update retains the previous graph.
Unchanged nodes are reused, changed credentials rebuild dependent groups, and
selected nodes are retained when still present. Revision 4 transfers the live
selector choice before publishing replacement groups, including when the disk
cache is disabled or unavailable. Adding or reordering subscription nodes preserves
existing connections. Ordinary downloads use the last
working request profile first, run up to eight sources concurrently, and have no
retry sleeps. Manual updates share a two-second request budget per source across
compatibility profiles; bootstrap downloads have a separate fifteen-second budget.
Network failures retain the working cache.

Changes to Happ routing/DNS or native AWG interfaces require Apply configuration;
the subscription button reports this instead of restarting services. A concurrent
explicit LuCI Apply remains queued independently. The subscription update itself
never creates a pending lifecycle reload.

`tests/dynamic_provider_runtime.py` verifies actual proxy traffic, unchanged PID,
continuous API availability, an existing connection, selected-node preservation,
node deletion and rejection of invalid graphs. `test-runtime.sh` runs it against
the exact ARM64 binary through QEMU. Total download time still depends on the
subscription server; the hot apply operation does not wait for a service restart.
