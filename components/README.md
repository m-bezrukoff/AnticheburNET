# AnticheburNET components

AnticheburNET is intended for all devices running OpenWrt 25.12. Supported protocols include VLESS, Hysteria 2, XHTTP and AmneziaWG 3.1, with an optional full Xray 26.11.9 core. Current prebuilt components support mediatek/filogic and mediatek/mt7622 with aarch64_cortex-a53.
The component build and services are separate from the architecture-independent AnticheburNET backend.
Both targets use the same ARM64 userspace APKs. Go executables use `CGO_ENABLED=0`,
and AmneziaWG tools are statically linked. No target-specific kernel modules are
bundled; kernel dependencies come from the installed firmware's feeds.

For installation on the router, run the single SSH command in
[the OpenWrt 25.12 guide](../docs/OPENWRT-25.12.md#установка). It downloads the five required release APKs
from GitHub, verifies their SHA-256 checksums and installs the complete suite.
The commands below are for building packages on a Linux development host.

Build on Linux with Go 1.26.10 and the Filogic SDK pinned in `versions.env`:

```sh
bash build.sh 1.0.1 dist/filogic
bash components/build.sh 1.0.1 dist/filogic
```

The second command needs `strace`, `qemu-user`, `iproute2`, `iputils-ping`, `openssl`, Python 3 and sudo
for isolated network tests. See `.github/workflows/filogic-build.yml` for all host dependencies.
The build also installs ucode for end-to-end importer tests and compares gzip, bzip2, xz,
zstd and SquashFS compression of the full official geodata. gzip is selected because
base OpenWrt can expand it without extra decoder packages or kernel modules. The helper
keeps the expanded files in `/var/run` (RAM), leaving only the archive on flash.
Go inputs use `go.sum`; the SDK and official Xray archive are checked against SHA256.
UPX 5.2.1 is pinned and verified too. It packs the required Go executables and optionally Xray to fit the
component size budget; `upx -t` and all QEMU protocol tests run on the packed executables.
sing-box and AWG are built from the exact commits below. The sing-box build applies
reviewed patches to a private copy of metacubex/uTLS 1.8.7; the Go module cache remains unchanged.
`utls-modern-browser-presets.patch` supplies Firefox 148, Safari 26.3 and Firefox
hybrid/classical key reuse. `utls-chrome155.patch` ports the
[captured Chrome 155 ClientHello](https://github.com/refraction-networking/utls/commit/6ebdceb2607e8c72942805af16ed4b8f052ee509)
used by Xray 26.11.9, including trust anchor IDs and signature GREASE.
`chrome` now selects Chrome 155; `chrome155`/`hellochrome_155` and
`chrome133`/`hellochrome_133` select explicit versions. Import retains those choices.
Build tests compare generated wire bytes with the browser capture and verify hybrid
key shares and REALITY key ownership. This preset port does not add general ML-DSA
X.509 certificate support to the older TLS stack; use native Xray for that capability.
REALITY ML-DSA-65 proof verification remains enabled in sing-box.

Corresponding upstream source and licenses:

- [sing-box extended source](https://github.com/shtorm-7/sing-box-extended/tree/d9442d14b19ddd02605bf3ee893a171947038e19), GPL-3.0-or-later.
- [AmneziaWG Go 3.1 source](https://github.com/amnezia-vpn/amneziawg-go/tree/b5928efb6ca19f0153958460c3d141f04abc5c2e), MIT.
- [AmneziaWG tools 3.1 source](https://github.com/amnezia-vpn/amneziawg-tools/tree/ee0f0a9aa34ff0a0da4b3433b9512781cfe02843), GPL-2.0.
- [Xray 26.11.9 source](https://github.com/XTLS/Xray-core/tree/v26.11.9), MPL-2.0.

The extended snapshot retains its XHTTP implementation. Native Xray is a separate process
and uses a SOCKS bridge; sing-box does not embed Xray 26.11.9. AWG 3.1 is also a separate
official userspace daemon; it is not the more limited AWG endpoint embedded in extended.
This avoids relying on new AWG fields that the embedded endpoint does not expose.

Runtime tests launch the exact ARM64 binaries through QEMU. Hysteria 2 and Xray carry an HTTP
response to a local origin; AWG 3.1 performs a handshake and ICMP traffic between two network
namespaces with header protection, padding ranges, random trailers and disabled cookies.
These prove controlled protocol operation, not router throughput or every server option.

All selected packages must use at most 35,000,000 file/allocated bytes in the build.
AmneziaWG is retained when the complete set fits this budget. `AdvancedSecurity=on` is
normalized by the importer: tools' legacy flag has no corresponding official Go 3.1
UAPI field, and that daemon always runs AWG. `off` is rejected explicitly.

Services and user configuration are documented in [the OpenWrt 25.12 guide](../docs/OPENWRT-25.12.md).

## Dynamic subscription providers

Component `sing-box-extended` 1.14.3-r8 (`anticheburnet.8`) includes the managed
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

## Optional Xray and security

The source build excludes Xray unless `BUILD_XRAY=1` is set. Its separate APK is selected by the installer and updater when enabled native Xray profiles or an enabled standalone Xray service require it; otherwise it remains optional. The release workflow defaults to publishing that asset for older updaters and native profiles. The UI reconciles completed legacy jobs through suite format 2 and removes unused Xray. See [migration details](../docs/XRAY-OPTIONAL-MIGRATION.md).

Connection JSON entries support `{ "type": "xray", "tag": "name", "config": { "outbounds": [...] } }`.
The editor also accepts the native config directly after selecting the Xray engine.
Up to eight distinct profiles run as private procd instances. Only loopback SOCKS
ingress and the TPROXY bypass mark are managed; XDRIVE, Finalmask, mux.cool,
VLESS Encryption and other native settings remain in Xray. Invalid configs are
rejected before Apply stops services. Unchanged profiles keep their process;
failed replacements restore the previous definition. Subscription hot updates
preserve native instances and require Apply if a native config changed.
Runtime manifests/configs use mode 0600 and a private RAM directory.
The native traffic test exercises XDRIVE local storage with VLESS Encryption and
mux.cool, through the same config preparer and sing-box SOCKS bridge. It does not
validate live Google Drive/S3 credentials or router throughput.

Builds require Go 1.26.10 and pin security updates for x/crypto, x/net and x/sys in versions.env. prepare-security.py adds REALITY ML-DSA-65 verification; invalid or missing proofs fail authentication. The managed provider uses the scoped lifecycle of extended 2.7.3 while retaining atomic graph/ruleset updates, selection and existing connections. Optional builds run tests/xray_compat_runtime.py against the exact ARM64 artifacts through QEMU.

Revision 7 disables MPTCP by default in sing-box, including API listeners. CI traces
the packed ARM64 core under QEMU to verify TCP sockets for IPv4, IPv6, TCP Fast Open
and Clash API, with explicit MPTCP as a positive control. The optional Xray 26.11.9
release independently disables MPTCP by default. Explicit MPTCP options can still
enable it; updating these applications does not replace a required kernel fix.
