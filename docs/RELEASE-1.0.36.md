# AnticheburNET 1.0.36

Dashboard subscription latency checks retain the complete HTTP/TLS round trip through each tested server. Under HAPP Rules and Tunnel everything, terminal subscription sockets now use the router's interception-bypass mark even when the subscription supplies another socket mark. This prevents policy interception from sending a tested connection through the currently selected tunnel as an additional hop.

Server hostnames in both global routing policies use direct bootstrap DNS. Local Clash API latency requests also ignore ambient proxy variables and curl configuration. TLS settings, URLTest targets and explicitly configured subscription chains are preserved. Selected routing retains subscription-provided socket marks.

Regression coverage includes both global policies, selected routing, TCP/UDP interception guards, individual and group latency API requests, and configurations with inline outbounds or the dynamic subscription provider.

AnticheburNET, LuCI and Russian translations are rebuilt as APK and IPK packages. Unchanged ARM64 cores are reused from the tested 1.0.35 release with matching pinned versions and SHA-256 verification. Physical-router firewall/TPROXY acceptance remains unverified.
