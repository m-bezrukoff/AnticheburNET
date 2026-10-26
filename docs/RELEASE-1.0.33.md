# AnticheburNET 1.0.33

Local Xray is optional. Clean installations and updates select five required packages and remove previously installed `anticheburnet-xray` or `xray-core` after configuration backup and dependency checks. The release still provides an optional Xray 26.10.21 APK so older six-package updaters can migrate. Updated LuCI continues the migration using the new backend; unattended legacy updaters complete it on their next run.

sing-box is rebuilt from extended 1.14.3-2.7.3 with AnticheburNET patches, Go 1.26.10 and updated security dependencies. REALITY MLDSA65 verification (`pqv` / `mldsa65Verify`) is supported. Import fixes preserve XHTTP extra settings and separate download configuration, accept the current REALITY password field, and explicitly reject unsupported transports and Finalmask. VLESS and Trojan validation follows the backend's supported transports.

Happ rule-set updates use the runtime provider to replace validated resources atomically while preserving active connections. Failed changes roll back without replacing the running configuration.

Country filtering uses a bundled DB-IP Country Lite IPv4/IPv6 database instead of sending server addresses to `api.country.is`. Existing filters retain their settings. The database adds approximately 3.93 MiB of flash storage and uses approximately 7.96 MiB of RAM when first unpacked. Attribution and the GeoIP helper are included in the packages.

All ARM64 components are rebuilt from pinned sources. The build checks core vulnerabilities, provider updates, protocol interoperability with Xray 26.10.21, and ARM64 execution under QEMU before publication. Application, LuCI and Russian translations are rebuilt as APK and IPK packages.

See [migration details](XRAY-OPTIONAL-MIGRATION.md), [compatibility audit](XRAY-26.10.21-COMPATIBILITY.md), and [local GeoIP](LOCAL-GEOIP.md). The separate [security audit](SECURITY-AUDIT-2026-10-26.md) records additional findings against 1.0.32; this release does not claim to resolve every finding in that audit.

Publishing this release does not install it or restart services on a router.
