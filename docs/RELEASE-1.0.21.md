# AnticheburNET 1.0.21

Active connection profiles are preserved across subscription refreshes, component updates and service restarts when the selected profile remains available. Component replacement saves the selection before stopping the runtime and restores it after startup. If a profile has been removed, its group uses an available default.

Dashboard now has **Update subscriptions daily at 03:00 (router time)**. It is enabled by default for new and existing installations, saves immediately, and replaces the previous per-subscription interval controls. Turning it off removes automatic subscription jobs. A manual daytime refresh does not delay the next 03:00 refresh.

New subscription connections are applied automatically without Save & Apply. The sing-box provider transfers the live selection before publishing rebuilt groups, including with the disk cache disabled. Unchanged connections remain open. New native AWG interfaces are prepared and checked for readiness before publication; rejected updates retain the previous working graph. Unrelated routing changes still require Save & Apply.

The release rebuilds the application, LuCI, Russian translation and ARM64 components. The sing-box component is updated to **1.14.1-r4**, with runtime version **1.14.1-extended-2.7.2-anticheburnet.4**. The component runtime checks include real traffic through subscription additions, reordering, profile removal and rejected updates, with an established connection held open during addition.

Publishing this release does not install it on a router.
