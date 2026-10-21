# AnticheburNET 1.0.31

Selected tunnels are now preserved when automatic DNS failover reloads sing-box, including the fallback service reload and configuration rollback. If the current choice cannot be captured or saved, the DNS reload is cancelled. Restoration retries temporarily unavailable provider groups and retains the saved choice if recovery remains pending.

A shared status strip at the top of all seven LuCI tabs shows service startup, shutdown, restart and configuration application. It follows runtime state and in-progress actions, stays visible when switching tabs or re-rendering forms, and disappears when the operation finishes. The strip inherits the active LuCI theme, includes Russian translations and supports reduced motion.

Validation includes DNS selection preservation and rollback scenarios, 556 frontend tests, lint, TypeScript/build checks, localization parity, and local browser checks on wide and narrow layouts. Synthetic browser previews do not establish live-router acceptance.

Application, LuCI and Russian translation packages are rebuilt. Unchanged ARM64 component packages are reused from release **1.0.30** with SHA-256 verification.

Publishing this release does not install it or restart services on a router.
