# AnticheburNET 1.0.24

Restores startup after an upgrade when a failed older AWG runner left subscription interfaces behind. Recovery only terminates an unregistered, orphaned process from a replaced AWG executable after checking its PID birth time, interface state, addresses, routes, rules and readiness. Running or manually configured tunnels are preserved.

Native subscription AWG endpoints now resolve through the configured bootstrap DNS before device configuration. Startup and HAPP resource downloads no longer depend on dnsmasq or the main sing-box instance already working. The saved profiles and router DNS configuration are not changed. Resolution has bounded timeouts and follows the configured bootstrap resolver list.

The package upgrade hook detects the old orphan state and schedules startup after the update worker and package manager finish. This also handles updates launched by versions that skip restarting an already failed service. Services deliberately stopped without the old orphan condition remain stopped.

The private HAPP download proxy now uses BusyBox-compatible readiness waits. Regression checks cover bootstrap DNS failover, IPv6, invalid endpoints, orphan ownership and PID reuse, active tunnel preservation, delayed startup, and backend package contents.

Application, LuCI and Russian translation packages are rebuilt. ARM64 component binaries are unchanged from 1.0.23.
