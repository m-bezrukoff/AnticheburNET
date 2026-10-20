# AnticheburNET 1.0.30

Component updates now capture the selected tunnel before package installation and restore that choice after the service restarts, including recovery after a failed sing-box update. Package hooks restarting an engine during installation no longer make the updater use the resulting default selection.

If the API or provider groups are temporarily unavailable, restoration is retried and the saved selection remains available for a later service start. A profile removed from its group falls back to an available profile.

Regression checks cover component restarts, package hooks, rollback, unavailable APIs and partially loaded provider groups.

Application, LuCI and Russian translation packages are rebuilt. Unchanged ARM64 component packages are reused from release **1.0.29** with SHA-256 verification.

Publishing this release does not install it or restart services on a router.
