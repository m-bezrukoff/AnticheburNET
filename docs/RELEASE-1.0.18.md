# AnticheburNET 1.0.18

AWG profiles added to an existing subscription now apply automatically through **Update subscriptions**, including scheduled refreshes. Adding, rotating or removing a native AWG profile no longer requires **Save & Apply**. The running sing-box process and unchanged AWG instances are preserved.

New interfaces start in free routing slots and must become ready before their proxy entries are published. Existing profiles keep their interface names when subscription entries are reordered. Obsolete interfaces are removed only after the dynamic provider confirms the replacement graph. A rejected update restores the previous provider; an uncertain API outcome retains both sets of interfaces until a retry confirms which graph is active.

The installed AmneziaWG component and an active dynamic sing-box provider are required. Changes outside the proxy list, including routing configuration, still require applying the configuration. At most 32 native AWG routing slots are supported; safe rotation needs a free slot while the previous profile remains active.

Regression coverage includes profile addition, reordering, rotation, removal, readiness timeout, failed instance registration, provider file failure, confirmed rollback, uncertain API responses and retryable cleanup. The focused tests also passed under the router's native ucode interpreter with isolated files and intercepted service operations. Live subscription application on the router has not been performed for this release.

The release includes six APK packages for OpenWrt 25.12 on supported aarch64_cortex-a53 targets, three generic application/LuCI/translation IPK packages, the installer and both checksum manifests. Application and LuCI packages are rebuilt for 1.0.18. Unchanged ARM64 cores are reused from the verified 1.0.17 release.
