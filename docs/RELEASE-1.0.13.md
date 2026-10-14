# AnticheburNET 1.0.13

Caches converted GeoIP and GeoSite rule sets used by Happ. Repeated subscription updates reuse the converted file instead of parsing the entire DAT again. The cache is bound to the source URL, DAT contents, entry/attribute, converter format, and converted-file contents. Changed, missing, or corrupt inputs invalidate it; previous rule-set files remain available for rollback. Warm cache hits do not read the full DAT into ucode.

The subscription, runtime, and UI paths share cached sing-box version output tied to the executable. File replacement or modification invalidates the version cache. SHA256 results are also cached for unchanged files; recently written files are hashed again to detect same-size changes inside the filesystem timestamp window. A failed probe cannot return an older version.

The production background subscription worker now performs the update directly, avoiding nested CLI processes. Already prepared runtime directories also avoid redundant interpreter launches; custom worker binaries and directory creation retain their existing behavior.

Verified over SSH on a Redmi AX6000 running OpenWrt 25.12.2 and sing-box r3. Before the fix, the recorded refresh took 17.708 seconds, including 12.519 seconds converting GeoIP and approximately 1.93 seconds probing the core version. After priming the caches, source processing and provider application took 1.007–1.043 seconds. Three final background jobs completed successfully in 1.490–1.592 seconds, with start responses in 85–98 ms. The sing-box process was preserved. These are observed timings, not a hard deadline for subscription servers; the first conversion and version probe after cache loss still require preparation.

Application packages are rebuilt for 1.0.13. Unchanged ARM64 components are reused from the tested 1.0.10 release.
