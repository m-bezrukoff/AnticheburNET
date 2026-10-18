# AnticheburNET 1.0.20

Fixes applying a changed global routing strategy or tunnel connection. Save & Apply now rebuilds both sing-box and nftables, so the saved HAPP, direct-with-exceptions or full-tunnel strategy is reflected in the running proxy configuration. Previously, Apply could rebuild only nftables, leaving subscription refreshes blocked with "Subscription routing changed; Apply configuration is required".

Dashboard shows that persistent Apply requirement once per browser tab session instead of adding another identical notification for every hourly subscription retry. Other errors retain their existing notification behavior.

After installing this version, apply the saved configuration once to reconcile a previously skipped routing change. Applying it can restart sing-box. Subscription refreshes continue to preserve running services when unrelated routing changes have not been applied.

Application and LuCI packages are rebuilt for 1.0.20. Unchanged ARM64 component packages are reused from 1.0.19.
