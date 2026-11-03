# AnticheburNET 1.0.35

Security update: sing-box extended is rebuilt as `1.14.3-extended-2.7.3-anticheburnet.7` with MPTCP disabled by default across its TCP listeners, including the API. This reduces exposure to the Linux MPTCP vulnerability addressed by Xray 26.10.31. Explicit `tcp_multi_path: true` can still enable MPTCP; affected Linux kernels need their own firmware security update.

The optional native Xray package is updated from 26.10.21 directly to 26.10.31 with pinned release archive SHA-256 checksums. Xray 26.10.29 was withdrawn upstream. Standard installation and updates continue to select five required packages and migrate away from an installed optional Xray according to the existing policy; the Xray asset remains available for older updaters and explicit native use.

The release builds fresh ARM64 components. CI traces socket creation by the exact UPX-packed sing-box through QEMU: default IPv4, IPv6, TCP Fast Open and Clash API listeners must use TCP without attempting MPTCP. An explicitly enabled MPTCP listener is the positive control. Existing provider, Xray interoperability, Hysteria 2, AmneziaWG and installed-size checks run before publication. Backend, LuCI and Russian translations are rebuilt as APK and IPK packages.

VLESS/Vision, REALITY, XHTTP, VLESS Encryption, gRPC and the SOCKS bridge were tested locally against both new Xray versions before this change. Native Xray now rejects unencrypted VLESS to CGNAT addresses such as `100.64.0.1`; use TLS, REALITY or VLESS Encryption for those native profiles. Physical-router firewall/TPROXY behavior and throughput are not established by the local and QEMU checks.
