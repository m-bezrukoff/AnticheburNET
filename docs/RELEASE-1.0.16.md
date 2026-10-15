# AnticheburNET 1.0.16

The Components tab now offers an **Automatically update every 3 days at 04:00** checkbox above the main **Check update** button. It saves immediately and defaults to disabled. The first automatic run is scheduled three calendar days after enabling, at 04:00 in the router's local timezone. The persistent calendar guard handles month boundaries, leap years, daylight-saving changes, reboots, and missed windows.

A second line below the checkbox shows the router-local date, time, and result of the last automatic run: updated, already up to date, failed, in progress, or interrupted. History survives reboots and disabling the checkbox; manual updates do not overwrite it. A router reboot or replaced worker cannot leave a stale run permanently marked in progress.

The main AnticheburNET card fills the available width. Fixed-width Zapret, Zapret2, and ByeDPI cards appear in one row aligned to the right. The separate Sing-box card is hidden; sing-box extended remains part of the complete release update.

Automatic updates use the same guarded complete-suite update as the main button. An already current suite is not reinstalled. Settings preservation, configuration backups, SHA256 verification, and deferred package restarts are retained. Zapret, Zapret2, and ByeDPI retain their separate controls and are excluded from automatic complete-suite updates.

The full package set includes six APK packages for OpenWrt 25.12, mediatek/filogic, aarch64_cortex-a53; three generic application/LuCI/translation IPK packages; the installer; and both checksum manifests. Application and LuCI packages are rebuilt for 1.0.16. Unchanged ARM64 cores are reused from the verified 1.0.15 release.
