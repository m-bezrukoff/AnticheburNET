# AnticheburNET 1.0.8

AmneziaWG runners now wait for their control socket using millisecond sleep in ucode, fixing startup on BusyBox builds that only accept integer seconds. The AmneziaWG component package revision is updated to `3.1.20260828-r4`.

Dashboard latency tests run up to eight probes concurrently and report progress as responses arrive. URLTest groups are checked after ordinary proxies. Transport failures and invalid responses are counted without stopping the remaining probes.

Dashboard now keeps a compact service status row and removes the three unavailable traffic and system widgets. Subscription servers, including AmneziaWG, remain in the common server list.

This release includes the Check update progress bar and bounded update recovery introduced in 1.0.7. Backend, LuCI, Russian translations and all ARM64 components are rebuilt together on GitHub.
