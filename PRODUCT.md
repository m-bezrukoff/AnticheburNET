# AnticheburNET

OpenWrt application for configuring network routing, proxy connections and optional traffic-processing components through LuCI.

The application has seven main tabs: Dashboard, Sections, Servers, Settings, Diagnostics, Monitoring and Components. Sections contains the global routing strategy and the HAPP rule/resource inspector. Section and server editors use standard LuCI dialogs and form controls.

The primary audience is the router administrator. This is an Operate surface: make configuration, connection selection, runtime status and recovery actions easy to scan without obscuring technical details.

Preserve LuCI's form validation, dependency visibility, save/apply lifecycle, keyboard interaction, localization and active theme. Display backend state faithfully. A saved HAPP configuration or a prepared geodata resource does not by itself prove that changes are applied to the live router.

The October 2026 visual update was approved first as a HAPP mockup and then extended by the user to every application section. It changes presentation; it does not authorize changing router configuration, installing a release or restarting services.
