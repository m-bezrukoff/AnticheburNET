# AnticheburNET 1.0.38

- Full tunnel and HAPP skip nftables sets reserved for selective routing. Device-specific DNS reaches its listener before TPROXY can capture it. The QUIC setting covers IPv4 and IPv6, and the NTP exception covers clients and the router itself.
- Full-tunnel DNS failover probes use the same outbound as the active resolver. Bootstrap DNS stays direct. Subscription and GeoIP/GeoSite updates can proceed after resolver failover while preserving the applied DNS settings.
- Dashboard latency checks use the configured target and report HTTP failures. Local Clash API requests use bounded timeouts and authenticate when YACD has a configured secret. Dashboard and Monitoring use RPC when the browser cannot reach the WebSocket stream.
- Subscription downloads explicitly select curl's proxy behavior. List updates go straight to the configured sources. Manual and subscription Shadowsocks links share a parser that preserves escaped passwords and literal Base64 characters.
- The sing-box component advances to `1.14.3-extended-2.7.3-anticheburnet.9` (`1.14.3-r9`). Dynamic provider validation resolves endpoint dependencies in one graph traversal. LuCI detects Tailscale from the installed core's build tags.
