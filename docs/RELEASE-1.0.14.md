# AnticheburNET 1.0.14

The AnticheburNET **Check update** button now updates the complete release for the device: the application, LuCI, the installed Russian translation, sing-box extended, Xray, and AmneziaWG. If the application is already current, the button still checks the bundled cores and updates outdated or missing cores. Zapret, Zapret2, and ByeDPI retain their separate update controls.

The sing-box component card displays its installed version without standalone check/update buttons. Its core is distributed with the matching AnticheburNET release.

Release packages are selected for the device architecture from one release and verified against its SHA256 manifest before installation. Incomplete or ambiguous core assets and foreign release URLs are rejected. Settings for AnticheburNET, sing-box, Xray, and AmneziaWG are backed up and preserved. Package hooks receive restart deferral through APK's preserved environment; the parent service restarts after the package transaction and settings restoration.

Application and LuCI packages are rebuilt for 1.0.14. Unchanged ARM64 cores are reused from the tested 1.0.13 release. The complete APK suite targets OpenWrt 25.12, mediatek/filogic, aarch64_cortex-a53.

Install through the AnticheburNET **Check update** button in LuCI's Components tab.
