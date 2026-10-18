# AnticheburNET 1.0.23

Fixes service startup after a router reboot when an AWG server name cannot yet be resolved. Stopping AWG during endpoint resolution now interrupts configuration and cleans up the child process before procd's termination deadline. This prevents orphaned AWG processes and interfaces from blocking later automatic startup attempts after WAN becomes available. Both subscription and standalone AWG runners include the fix.

HAPP geodata preparation errors now retain the underlying AWG failure. Startup notifications show the actual error instead of the final source-code pointer from a ucode stack trace.

The AmneziaWG component package is updated to **3.1.20260828-r5** so the corrected standalone runner is installed during a full-suite update. Application, LuCI, Russian translation and ARM64 component packages are rebuilt for this release.

Regression checks cover interrupted endpoint resolution, child-process cleanup, successful AWG setup, configuration failures and error reporting. The interruption scenario was also tested with isolated command doubles on the router's BusyBox shell.

Publishing this release does not install it or restart services on a router.
