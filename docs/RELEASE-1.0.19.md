# AnticheburNET 1.0.19

The **Sections** page now has a global **Routing strategy** selector above the section list:

1. **HAPP rules: all through the tunnel except exclusions** — use the selected subscription's ordered Direct/Proxy/Block rules, GeoIP/GeoSite, Remote/Domestic DNS and DnsHosts, with the tunnel as the default exit.
2. **Direct by default, exceptions through the tunnel** — retain section-based routing, with unmatched traffic going directly. This is the default strategy.
3. **All through the tunnel** — route intercepted TCP/UDP traffic and the main DNS resolver through the selected connection without applying HAPP or section conditions.

The first and third strategies have a **Tunnel connection** selector; automatic selection uses the first enabled connection. An explicitly selected missing or disabled connection is rejected. HAPP mode requires an enabled routing profile in that connection's subscription. The global tunnel strategies ignore section destination, device and port conditions and enable interception of real IPv4 and IPv6 addresses. Local destinations and tunnel bootstrap traffic retain the service's routing safeguards. Apply configuration changes with **Save & Apply**.

Recognized BitTorrent traffic goes directly before HAPP and section routing in all strategies. Detection covers ordinary BitTorrent TCP handshakes, uTP and UDP tracker connection packets, regardless of peer port. Encrypted peer traffic, DHT and HTTP(S) trackers are not guaranteed to be recognized; guaranteeing direct routing for an entire torrent client requires a device/IP routing policy. Per-section SOCKS/HTTP listeners also perform protocol detection.

The old implicit activation of subscription routing is replaced by the explicit global strategy. To continue using subscription exclusions after updating, select the HAPP strategy. With the default direct strategy, subscription metadata no longer changes routing automatically.

The release includes six APK packages for supported OpenWrt 25.12 aarch64_cortex-a53 targets, three generic application/LuCI/translation IPK packages, the installer and both checksum manifests. No router configuration is applied by publishing this release.
