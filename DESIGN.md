# AnticheburNET interface

Use the existing LuCI theme and the original per-tab styles for the application, forms, tables, controls and dialogs. Do not add a shared application-wide visual override.

## Sections and HAPP

Keep the HAPP rule/resource visualization in the Sections tab: full-width profile panels, grouped rules, resource states, disclosures and responsive columns. Its implementation lives in `luci-app-anticheburnet/htdocs/luci-static/resources/view/anticheburnet/happ.js`.

Inherit the system font from the active LuCI theme, including literal rule lists. Preserve the visualization's heading hierarchy, icons, spacing and status colors. Do not force a separate application font family or body size.

Keep section and server editors and the surrounding routing controls in their original LuCI design.

## Behavior

Preserve validation, dependency visibility, localization and save/apply behavior. Keep saved, prepared and applied states distinct. Preserve disclosures, focus and rule-list scrolling across polling updates. Render subscription-provided values as text nodes. Resource links retain their full original destination.

Verify local previews with synthetic data separately from live-router behavior.
