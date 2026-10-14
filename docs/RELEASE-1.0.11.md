# AnticheburNET 1.0.11

Fixes subscription updates failing with `Type error: left-hand side is not a function` in `subscription/cache.uc`. The result collector now uses the available ucode `trim()` function when reading each download worker's status file, allowing updates to finish and report their results.

The parallel subscription regression test now also executes the production result collector. It covers eight scenarios, including changed and unchanged sources, failed and superseded updates, whitespace around status codes, missing or invalid results, skipped sources, and temporary-file cleanup.

AnticheburNET and LuCI packages are rebuilt for 1.0.11. The unchanged ARM64 sing-box, Xray, and AmneziaWG component packages are reused from the tested 1.0.10 release. Existing dynamic-provider behavior is retained.
