# AnticheburNET 1.0.37

Transparent UDP routing on sing-box 1.14 and newer now keeps a separate session for each destination address and port. A torrent client's first DHT packet can no longer select the tunnel for uTP peers at other destinations that share its local UDP port. The fix covers IPv4, IPv6 and all three routing strategies. Regression tests exercise the pinned core's NAT and BitTorrent sniffers, reproduce the previous behavior, and verify the corrected mapping.

The interface now describes the actual scope of the BitTorrent exception. Detected BitTorrent goes directly; encrypted TCP peer connections, DHT and HTTP(S) trackers still follow ordinary routing rules. Excluding an entire torrent client requires a separate direct route for that application's traffic.

Native Xray 26.11.9 profiles can be selected in the connection JSON editor. Their native outbound settings, including XDRIVE, Finalmask, VLESS Encryption and mux.cool, are retained behind managed loopback SOCKS listeners. Up to eight distinct profiles are supported, with private runtime files, validation before applying, preservation of unchanged instances, and rollback when a replacement fails. The installer and complete-suite updater retain or install the optional Xray package when enabled native profiles or the standalone service require it. Native profile changes require Apply instead of restarting services during a subscription refresh.

The sing-box component advances to `1.14.3-extended-2.7.3-anticheburnet.8`, with the Chrome 155 uTLS preset and explicit Chrome 155/133 aliases. Fingerprint imports preserve these selections and reject unsupported older component revisions. REALITY ML-DSA proof verification remains enabled. This preset update does not add general ML-DSA X.509 certificate validation to the sing-box TLS stack.

Diagnostics mask credentials in multiline native JSON entries, including escaped quotes. Dashboard latency requests treat HTTP errors as failures rather than accepting an error body as a measurement.

The release contains rebuilt backend, LuCI and Russian translation APK/IPK packages, plus ARM64 sing-box, AmneziaWG and optional Xray APKs. The component workflow validates the packed ARM64 artifacts with QEMU and controlled protocol traffic. XDRIVE tests use a local file backend; live Google Drive/S3 credentials and physical-router throughput are outside these checks. Installing the release and applying its configuration remain separate from publishing it.
