# AnticheburNET 1.0.5

The project, OpenWrt packages, LuCI menu, RPC permissions, services, configuration and runtime paths now use AnticheburNET / anticheburnet.

The program's **Check update** button checks the latest GitHub release and installs a newer version in one action. Package checksums are verified, the configuration and persistent data are backed up, and backend, LuCI and translation packages are installed together. Existing user settings are retained. Background checks only report available updates.

Subscription TLS fingerprints are preserved. Current Firefox and Safari browser presets support REALITY connections to Xray 26.10.10. HAPP subscriptions using real DNS addresses are routed through sing-box for policy selection. Diagnostic proxy requests follow the active selector.

All six ARM64 packages target OpenWrt 25.12 on Filogic / aarch64_cortex-a53. Use the release installer to install the renamed application after uninstalling the previous program.

Backend upgrades preserve the separately managed sing-box binary and service. Self-update restarts the application after the APK package transaction finishes. Configuration and subscription device identity are retained. The ARM64 cores are unchanged from the successful 1.0.2 hardware build and retain their tested checksums.

Failed-start retry workers release the procd file descriptor, keeping service start, stop and update operations responsive.

WAN recovery queues restart and reload after their procd handler releases its lock, preventing a recursive service lock during boot.

Cold startup generates HAPP routing and downloads geodata before enabling traffic interception, so bootstrap requests are not sent to a proxy that has not started yet.
