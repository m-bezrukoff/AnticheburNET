# AnticheburNET 1.0.15

The main **Check update** action completes the entire bundled release with one click: AnticheburNET, LuCI, the installed Russian translation, sing-box extended, Xray, and AmneziaWG. Updates started by an older application-only updater continue the original job automatically until the bundled cores are complete. The continuation is pinned to the release just installed.

Pressing the update button again when the complete release is current does not download packages, reinstall them, or restart the service. The backend also checks LuCI and translation versions, guards direct install requests, and verifies the installed suite before reporting success. Failed or incomplete updates remain errors; concurrent status requests cannot launch duplicate completion workers.

Configuration backup, SHA256 verification, settings preservation, and deferred package restarts are retained. Zapret, Zapret2, and ByeDPI keep their separate update controls and remain outside this release transaction.

Application and LuCI packages are rebuilt for 1.0.15. The unchanged ARM64 cores are reused from the verified 1.0.14 release. The complete APK suite targets OpenWrt 25.12, mediatek/filogic, aarch64_cortex-a53. Generic application, LuCI, and Russian translation IPK packages are also included.

Install through **Check update** in LuCI's Components tab.
