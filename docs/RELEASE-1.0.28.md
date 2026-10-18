# AnticheburNET 1.0.28

FakeIP diagnostics now accept matching public IPs when HAPP or all-through-tunnel routing sends both diagnostic requests through the same tunnel. The check inspects the generated sing-box routing configuration, including dynamic provider configuration, rather than relying on the selected settings alone.

When FakeIP works on the router and in the browser, and the shared tunnel route is confirmed, the check is green and explains that matching public IPs are expected. Selective routing retains the warning for an inconclusive comparison. Failed or unavailable DNS/browser checks, failed control requests and empty public IP responses remain visible.

Application, LuCI and Russian translation packages are rebuilt. ARM64 component binaries are unchanged from 1.0.27. Regression checks cover HAPP and tunnel routing, selective and restricted routes, dynamic providers, unavailable configuration and diagnostic failures. All 545 frontend tests pass.

Publishing this release does not install it or restart services on a router.
