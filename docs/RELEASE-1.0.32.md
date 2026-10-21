# AnticheburNET 1.0.32

New installations default to **All through the tunnel** in both the packaged configuration and LuCI. Existing saved routing strategies are preserved.

Package installation enables service autostart and requests service startup. The complete-suite installer starts the service after all components are installed; deferred package updates continue to leave startup to the installer or component worker. If no usable tunnel connection is configured, startup failure is reported without failing package installation. Add an enabled connection in LuCI and apply the configuration to begin routing traffic.

The Sections view no longer displays the subscription configuration notice above HAPP profiles. Profile rules, resources and status remain available.

Application, LuCI and Russian translation packages are rebuilt. Unchanged ARM64 component packages are reused from release **1.0.31** with SHA-256 verification.

Publishing this release does not install it or restart services on a router.
