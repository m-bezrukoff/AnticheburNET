# AnticheburNET interface

## Overview

Use the approved HAPP composition as the shared visual language for all seven LuCI tabs and their editors. Keep each tab's existing task-specific layout and behavior. The UI is compact, flat and readable, with clear distinctions between headings, technical data, metadata and actions.

The source of shared styling is `fe-app-anticheburnet/src/interfaceStyles.ts`, included by `src/styles.ts` and compiled into the LuCI `main.js` bundle. The HAPP inspector is implemented separately in `view/anticheburnet/happ.js` and aliases the shared tokens.

## Colors

Inherit the active LuCI theme. The application does not force a theme or restyle the LuCI navigation shell. `--ac-text` uses `--text-color-high`; `--ac-muted` mixes that foreground at 78%; `--ac-border` uses it at 20%; `--ac-surface` and `--ac-hover` use 3% and 6% tonal surfaces. `--ac-accent`, `--ac-success`, `--ac-warning` and `--ac-error` inherit LuCI's link and semantic colors.

Use the accent for actions, selection and keyboard focus. Success, warnings and errors always have text or icons as well as color. Neutral states such as an unused GeoSite resource do not appear as errors.

## Typography

Use the system sans family with a 14px body and 1.5 line height. Application titles are 24px, section headings 20px and component headings 16–17px. HAPP uses a 22px title and 19px profile name. Secondary copy is 13px. Use monospace for literal rule strings and tabular numerals for measurements and timestamps.

## Layout

Use 12–18px group spacing and 10–14px panel padding. Panels have content-aligned headings and concise metadata. Tables use restrained headers; avoid empty padded panels for missing content.

HAPP spans the full form width. It presents the update instruction, profile metadata, routing rules and resource states in that order. Populated actions open initially; empty actions are short collapsed disclosures. The displayed rule groups do not change the backend evaluation order. Preserve disclosures, keyboard focus and rule-list scrolling across polling updates.

At narrow container widths, form labels move above inputs, rules become one column, zone tables become labeled rows, component groups wrap and Diagnostics becomes one column. Wide section/server tables scroll inside their own bounds. Preserve Monitoring's table scrolling and native table behavior.

## Elevation & Depth

Use 1px boundaries and subtle tonal layering. Avoid decorative shadows, glow, glass and gradients. Standard LuCI overlays retain their functional stacking and positioning.

## Shapes

Use the shared 5px corner radius. Standard buttons and inputs have a minimum height of 34px; compact icon and DynamicList controls preserve their existing geometry.

## Components

Shared styles are scoped to `.ac-app` and its open LuCI dialogs. The root class is attached to the rendered AnticheburNET form map. Keep loading, disabled, selected, invalid, empty and error states visible. Use a 2px focus outline with offset rather than a glow. Icons use the existing Lucide outline vocabulary and proper SVG namespaces.

Resource links retain their complete original destination while displaying concise source names. Subscription-provided values must be text nodes, never HTML. Keep localization catalogs synchronized.

## Do's and Don'ts

- Preserve field names, routes, handlers, validation and save/apply behavior.
- Use factual backend states; distinguish selected, cached, prepared, saved and applied.
- Keep technical values readable and allow long names and sources to wrap.
- Do not let global styles leak into other LuCI applications.
- Do not invent charts, metrics, catch-all routing rules or automatic actions.
