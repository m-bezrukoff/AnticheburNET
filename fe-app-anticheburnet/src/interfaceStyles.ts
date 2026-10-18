// Shared visual language for AnticheburNET's forms and custom tabs.
// Scope it to this map (and its open dialogs), never to the LuCI shell.
export const InterfaceStyles = `
:where(.ac-app, body:has(.ac-app) .modal) {
  --ac-text: var(--text-color-high, currentColor);
  --ac-muted: color-mix(in srgb, var(--ac-text) 78%, transparent);
  --ac-border: color-mix(in srgb, var(--ac-text) 20%, transparent);
  --ac-surface: color-mix(in srgb, var(--ac-text) 3%, transparent);
  --ac-hover: color-mix(in srgb, var(--ac-text) 6%, transparent);
  --ac-accent: var(--link-color, color-mix(in srgb, #007ea8 65%, currentColor));
  --ac-success: var(--success-color-medium, color-mix(in srgb, #27854d 65%, currentColor));
  --ac-warning: var(--warn-color-medium, color-mix(in srgb, #a56700 65%, currentColor));
  --ac-error: var(--error-color-medium, color-mix(in srgb, #c23d3d 65%, currentColor));
  --ac-radius: 5px;
  color: var(--text-color-high, inherit);
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  font-size: 14px;
  line-height: 1.5;
  min-width: 0;
  container-type: inline-size;
}
:where(.ac-app, body:has(.ac-app) .modal) :is(h2, h3, h4) {
  color: var(--ac-text); font-family: inherit; font-weight: 600;
  line-height: 1.35; letter-spacing: normal; text-shadow: none;
}
.ac-app h2 { font-size: 24px; margin: 0 0 18px; }
.ac-app h3 { font-size: 20px; margin: 18px 0 12px; }
.ac-app h4 { font-size: 16px; margin: 0 0 8px; }
.ac-app :is(.cbi-map-descr, .cbi-section-descr, .cbi-value-description) {
  color: var(--ac-muted); line-height: 1.5; overflow-wrap: anywhere;
}
:where(.ac-app, body:has(.ac-app) .modal) .cbi-value-description { margin-top: 6px; font-size: 13px; }
.ac-app .cbi-section { border: 0; box-shadow: none; background: transparent; padding: 0; margin: 16px 0; min-width: 0; }
:where(.ac-app, body:has(.ac-app) .modal) .cbi-value { padding-top: 10px; padding-bottom: 10px; }
:where(.ac-app, body:has(.ac-app) .modal) .cbi-value-title { font-weight: 500; line-height: 1.5; padding-top: 7px; }
:where(.ac-app, body:has(.ac-app) .modal) .cbi-value-field { min-width: 0; }
.ac-app [id$="-_mount_node"] { margin: 0; padding: 0; }
.ac-app [id$="-_mount_node"] > .cbi-value-title { display: none; }
.ac-app [id$="-_mount_node"] > .cbi-value-field { margin-left: 0; width: 100%; }
.ac-app .cbi-tabmenu {
  display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 18px;
  padding: 0 0 10px; border-bottom: 1px solid var(--ac-border); background: transparent;
}
.ac-app .cbi-tabmenu li { margin: 0; padding: 0; border: 0; background: transparent; }
.ac-app .cbi-tabmenu li a {
  display: block; padding: 7px 12px; border: 1px solid transparent;
  border-radius: var(--ac-radius); color: var(--ac-muted); text-decoration: none; font-weight: 500;
}
.ac-app .cbi-tabmenu .cbi-tab a { border-color: var(--ac-border); background: var(--ac-surface); color: var(--ac-text); }
.ac-app .cbi-tabmenu .cbi-tab-disabled a:hover { background: var(--ac-hover); color: var(--ac-text); }
:where(.ac-app, body:has(.ac-app) .modal) :is(.cbi-button, .btn) {
  min-height: 34px; padding: 6px 12px; border: 1px solid var(--ac-border);
  border-radius: var(--ac-radius); background: transparent; color: var(--ac-text);
  font: inherit; line-height: 1.4; text-shadow: none; box-shadow: none;
}
:where(.ac-app, body:has(.ac-app) .modal) :is(.cbi-button, .btn):hover:not(:disabled) { background: var(--ac-hover); }
:where(.ac-app, body:has(.ac-app) .modal) :is(.cbi-button-action, .cbi-button-apply, .cbi-button-save, .cbi-button-positive) {
  border-color: var(--ac-accent); color: var(--ac-accent); background: transparent;
}
:where(.ac-app, body:has(.ac-app) .modal) :is(.cbi-button-remove, .cbi-button-negative, .cbi-button-reset) {
  color: var(--ac-error); border-color: color-mix(in srgb, var(--ac-error) 60%, transparent); background: transparent;
}
:where(.ac-app, body:has(.ac-app) .modal) :is(.cbi-button, .btn):disabled { opacity: .5; cursor: not-allowed; }
:where(.ac-app, body:has(.ac-app) .modal) :is(input.cbi-input-text, input.cbi-input-password, select.cbi-input-select, textarea.cbi-input-text, .cbi-dropdown) {
  min-height: 34px; max-width: 100%; border: 1px solid var(--ac-border);
  border-radius: var(--ac-radius); box-shadow: none; background-color: var(--ac-surface);
  color: var(--ac-text); font: inherit; caret-color: var(--ac-accent);
  box-sizing: border-box;
}
:where(.ac-app, body:has(.ac-app) .modal) :is(input, textarea)::placeholder { color: var(--ac-muted); opacity: 1; }
:where(.ac-app, body:has(.ac-app) .modal) :is(input, textarea, select):disabled { opacity: .6; }
:where(.ac-app, body:has(.ac-app) .modal) :is(input, textarea, select).cbi-input-invalid { border-color: var(--ac-error); }
:where(.ac-app, body:has(.ac-app) .modal) :is(button, input, select, textarea, a, summary, [tabindex]):focus-visible {
  outline: 2px solid var(--ac-accent); outline-offset: 3px;
}
:where(.ac-app, body:has(.ac-app) .modal) input:is([type="checkbox"], [type="radio"]) { accent-color: var(--ac-accent); }
:where(.ac-app, body:has(.ac-app) .modal) a { text-underline-offset: 3px; }
:where(.ac-app, body:has(.ac-app) .modal) ::selection { background: var(--ac-accent); color: Canvas; }
.ac-app :is(.table, .cbi-section-table) {
  border: 1px solid var(--ac-border); border-radius: var(--ac-radius);
  background: transparent; box-shadow: none; margin: 12px 0; font-size: 14px;
}
.ac-app :is(.table, .cbi-section-table) :is(.tr, tr) { background: transparent; color: var(--ac-text); }
.ac-app :is(.table, .cbi-section-table) :is(.table-titles, .cbi-section-table-titles, thead tr) { background: var(--ac-surface); color: var(--ac-muted); }
.ac-app :is(.table, .cbi-section-table) :is(.th, th) { font-weight: 500; }
.ac-app :is(.table, .cbi-section-table) :is(.td, td, .th, th) { padding: 9px 12px; border-color: var(--ac-border); vertical-align: middle; }
.ac-app :is(.table, .cbi-section-table) :is(.tr, tr):hover { background-color: var(--ac-hover); }
.ac-app .cbi-section-create { margin-top: 12px; }
/* Keep each tab's task-specific layout; share the same quiet panel treatment. */
.ac-app :is(.fkp_dashboard-page__widgets-section__item, .fkp_dashboard-page__outbound-section,
  .fkp_dashboard-page__outbound-grid__item, .fkp_dashboard-page__subscription-meta,
  .fkp_diagnostic-page__right-bar__wiki, .fkp_diagnostic-page__right-bar__actions,
  .fkp_diagnostic-page__right-bar__system-info, .fkp_diagnostic_alert, .fkp_updates-page__component) {
  border-width: 1px; border-color: var(--ac-border); border-radius: var(--ac-radius);
  padding: 14px; box-shadow: none;
}
.ac-app :is(.fkp_dashboard-page__outbound-section__title-section, .fkp_updates-page__component__header) {
  border-bottom: 1px solid var(--ac-border); padding-bottom: 10px; margin-bottom: 2px;
}
.ac-app :is(.fkp_dashboard-page__outbound-section__title-section__title, .fkp_updates-page__component__title) { font-size: 17px; font-weight: 600; }
.ac-app .fkp_dashboard-page__outbound-grid__item { padding: 10px 12px; }
.ac-app .fkp_dashboard-page__outbound-grid__item--active { border-color: var(--ac-success); background: color-mix(in srgb, var(--ac-success) 5%, transparent); }
.ac-app .fkp_dashboard-page__outbound-grid__item--selectable:hover { border-color: var(--ac-accent); background: var(--ac-hover); }
.ac-app :is(.fkp_dashboard-page__widgets-section__item__row__key, .fkp_dashboard-page__subscription-meta__fact-key,
  .fkp_updates-page__component__info-label, .fkp_updates-page__component__header-version,
  .fkp_diagnostic_alert__description) { color: var(--ac-muted); }
.ac-app :is(.fkp_dashboard-page__widgets-section__item__row__value, .fkp_dashboard-page__outbound-grid__item__footer,
  .fkp_updates-page__component__info-value) { font-variant-numeric: tabular-nums; }
.ac-app .fkp_dashboard-page__outbound-grid { gap: 10px; }
.ac-app :is(.fkp_dashboard-page__widgets-section, .fkp_diagnostic-page, .fkp_diagnostic-page__left-bar,
  .fkp_diagnostic-page__right-bar, .fkp_diagnostic-page__checks, .fkp_updates-page__components,
  .fkp_updates-page__components-main, .fkp_updates-page__components-optional) { gap: 12px; min-width: 0; }
.ac-app :is(.fkp_diagnostic_alert__content, .fkp_diagnostic-page__left-bar, .fkp_diagnostic-page__right-bar) { min-width: 0; overflow-wrap: anywhere; }
.ac-app :is(.fkp_diagnostic_alert--success, .fkp_diagnostic_alert--warning, .fkp_diagnostic_alert--error) { color: var(--ac-text); }
.ac-app .fkp_diagnostic_alert--success { border-color: color-mix(in srgb, var(--ac-success) 60%, var(--ac-border)); }
.ac-app .fkp_diagnostic_alert--warning { border-color: color-mix(in srgb, var(--ac-warning) 60%, var(--ac-border)); }
.ac-app .fkp_diagnostic_alert--error { border-color: var(--ac-error); }
.ac-app .fkp_diagnostic_alert--loading { border-color: var(--ac-accent); }
.ac-app .fkp_diagnostic-page__right-bar__wiki--warning { border-color: var(--ac-warning); }
.ac-app .fkp_diagnostic-page__right-bar__wiki--error { border-color: var(--ac-error); }
.ac-app .fkp_diagnostic_alert--success .fkp_diagnostic_alert__icon { color: var(--ac-success); }
.ac-app .fkp_diagnostic_alert--warning .fkp_diagnostic_alert__icon { color: var(--ac-warning); }
.ac-app .fkp_diagnostic_alert--error .fkp_diagnostic_alert__icon { color: var(--ac-error); }
.ac-app .fkp_monitoring-page {
  --fkp-monitoring-divider-color: var(--ac-border);
  --fkp-monitoring-soft-bg: var(--ac-surface);
  --fkp-monitoring-soft-bg-hover: var(--ac-hover);
}
.ac-app .fkp_monitoring-page__panel { border: 1px solid var(--ac-border); border-radius: var(--ac-radius); padding: 14px; }
.ac-app .fkp_monitoring-page__controls { padding-bottom: 12px; border-bottom: 1px solid var(--ac-border); gap: 12px; }
.ac-app .fkp_monitoring-page__tabs { border-radius: var(--ac-radius); }
.ac-app .fkp_updates-page__components { flex-wrap: wrap; overflow-x: visible; }
.ac-app .fkp_updates-page__components-optional { flex: 1 1 300px; flex-wrap: wrap; }
.ac-app .fkp_updates-page__components-optional > .fkp_updates-page__component { flex: 1 1 220px; width: auto; min-width: 0; }
body:has(.ac-app) .modal {
  border: 1px solid var(--ac-border); border-radius: var(--ac-radius);
  box-sizing: border-box; min-width: 0; max-width: calc(100vw - 28px);
}
body:has(.ac-app) .modal .fkp-partial-modal__content { overflow: auto; scrollbar-color: var(--ac-border) transparent; }
body:has(.ac-app) .modal .fkp-partial-modal__footer { border-top: 1px solid var(--ac-border); padding-top: 14px; gap: 8px; }
@container (max-width: 680px) {
  .ac-app h2 { font-size: 21px; }
  .ac-app .cbi-tabmenu { gap: 2px; }
  .ac-app .cbi-tabmenu li a { padding: 6px 9px; }
  .ac-app .cbi-value-title, body:has(.ac-app) .modal .cbi-value-title { float: none; display: block; width: auto; text-align: left; padding: 0 0 6px; }
  .ac-app .cbi-value-field, body:has(.ac-app) .modal .cbi-value-field { margin-left: 0; width: 100%; }
  .ac-app .cbi-section-table { display: block; max-width: 100%; overflow-x: auto; scrollbar-color: var(--ac-border) transparent; }
  .ac-app .fkp_diagnostic-page { grid-template-columns: minmax(0, 1fr); }
  .ac-app .fkp_updates-page__components-main { min-width: 0; flex-basis: 100%; }
  .ac-app .fkp_updates-page__components-optional { flex-basis: 100%; }
  .ac-app :is(.fkp_dashboard-page__outbound-section__title-section, .fkp_updates-page__component__header) { flex-wrap: wrap; }
}
@media (prefers-reduced-motion: reduce) {
  .ac-app .skeleton::after, .ac-app .rotate { animation: none; }
  .ac-app .fkp_dashboard-page__outbound-grid__item__snake { display: none; }
}
`;
