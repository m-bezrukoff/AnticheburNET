# AnticheburNET 1.0.22

HAPP routing now treats manually entered domains on the selected tunnel connection as direct exceptions, with priority over subscription rules and resolution through the profile's Domestic DNS. Exact, suffix, keyword and regular-expression domain matches are supported for transparent traffic and the connection's SOCKS/HTTP listener.

Global tunnel strategies ignore saved section lists during startup, scheduled refreshes and manual list updates. Switching strategies preserves the saved lists for selected routing. Built-in list selection is hidden in HAPP mode; list and individual-domain fields are hidden in **All through the tunnel**. Recognized BitTorrent remains direct in every strategy, with a notice displayed beside the strategy selector.

GeoIP and GeoSite downloads now honor **Download lists through proxy** and its selected connection. A private temporary loopback proxy uses the prepared connection graph, including its dependencies, so downloads do not depend on an already-running or previously selected main listener. Downloads do not fall back to direct access on failure. The last good database is retained when a download or validation fails; the RAM cache remains valid for seven days.

The **Sections** page gains **HAPP rules and resources** with received Direct/Proxy/Block domain and IP rules, rule order, referenced GeoIP/GeoSite zones, whether each zone appears in the saved runtime configuration, resource URLs, download/cache status, timestamps, sizes and errors. Dynamic-provider configuration is included. These indicators describe saved configuration and resource preparation, not live rule-hit counters. Older normalized caches are identified until the next subscription refresh records the original received rule groups.

Application, LuCI and Russian translation packages are rebuilt for this release. Unchanged ARM64 sing-box, Xray and AmneziaWG component packages are reused from release **1.0.21** with checksum verification.

Publishing this release does not install it or apply configuration on a router.
