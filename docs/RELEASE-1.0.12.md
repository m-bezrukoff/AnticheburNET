# AnticheburNET 1.0.12

Repeated subscription refreshes reuse previously validated nodes when the downloaded body, request profile, final Happ routing headers, and normalized cache are unchanged. Every refresh still downloads the subscription and updates its traffic and expiry metadata. Changed nodes, routing, source settings, or cache contents invalidate reuse and go through the normal validation path.

Plain subscription bodies no longer launch gzip, gunzip, or zcat. Cache directory creation and permissions use native filesystem operations, and each download worker reuses its device ID, kernel version, and sing-box version. Automatic request profiles try the previously successful User-Agent first.

Regression checks cover response reuse, fresh metadata, profile and URL changes, Happ routing and redirects, modified caches, changed nodes, superseded settings, private cache permissions, and source removal. A local WebAssembly benchmark of the production collector with 1000 synthetic nodes reduced repeated processing from approximately 85 ms to 9–10 ms with downloads stubbed. These measurements exclude real network latency and are not a one-second end-to-end guarantee on a router. Debug logs now report source-processing and provider-application durations separately.

The application packages are rebuilt for 1.0.12; unchanged ARM64 components are reused from release 1.0.10.
