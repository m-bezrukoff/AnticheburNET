# AnticheburNET 1.0.29

In HAPP routing mode (all traffic through the tunnel except exclusions), SMTP connections to TCP destination ports **25, 465 and 587** now go directly instead of through the tunnel. The exception takes priority over subscription Proxy and Block rules and applies to both IPv4 and IPv6, including TLS and STARTTLS connections without protocol sniffing.

Other routing strategies and nonstandard SMTP ports retain their existing behavior. Regression checks cover strategy isolation and the priority of the generated SMTP route over HAPP subscription rules.

Application, LuCI and Russian translation packages are rebuilt. Unchanged ARM64 component packages are reused from release **1.0.28** with SHA-256 verification.

Publishing this release does not install it or restart services on a router.
