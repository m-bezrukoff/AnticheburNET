# AnticheburNET 1.0.7

**Check update** now displays a progress bar and the current operation: checking the release, resolving assets, downloading packages, verifying checksums, backing up settings, installing packages, restarting and waiting for the service. The bar counts completed stages; it does not claim a download percentage. Downloads show the package name and retry attempt.

The interface restores progress when reopening Components or after a temporary RPC interruption. The combined `check_and_update` action is now correctly associated with the Check update button. If the update state disappears and the installed version cannot be confirmed, recovery ends with an actionable error instead of an endless spinner.

Backend, LuCI and Russian translations are updated together. ARM64 sing-box, Xray and AmneziaWG packages are reused unchanged from the successfully tested 1.0.6 release and their checksums are verified during the build.
