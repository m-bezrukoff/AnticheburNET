# AnticheburNET 1.0.6

AmneziaWG profiles from plain INI `vpn://` subscription links now appear in the common Dashboard alongside VLESS and Hysteria, with selection and configuration copying. Full AWG 3.1 parameters are retained and applied through the official native AmneziaWG daemon.

The backend package includes the subscription interface service and runner. Updating from 1.0.5 through **Check update** therefore also installs the Dashboard AWG runtime integration while retaining the existing AmneziaWG 3.1 binaries. The AmneziaWG component must already be installed; the complete Filogic suite includes it.

Built-in subnet lists use curl for HTTPS downloads through the selected proxy, with bounded retries and no direct fallback when proxy routing is enabled.

This release includes backend, LuCI, Russian translations, sing-box, Xray and AmneziaWG packages for OpenWrt 25.12 / Filogic / aarch64_cortex-a53, plus SHA-256 manifests. After updating, refresh subscriptions on the Dashboard to import AWG profiles.
