"use strict";
"require baseclass";
"require fs";
"require poll";

// Keep the widget independent of the bundled frontend and inherit LuCI's theme.
const styles = `
.ac-happ-field > .cbi-value-title { display: none; }
.ac-happ-field > .cbi-value-field { margin-left: 0 !important; width: 100%; }
.ac-happ {
  --happ-border: var(--ac-border, var(--border-color-high, color-mix(in srgb, currentColor 20%, transparent)));
  --happ-muted: var(--ac-muted, color-mix(in srgb, currentColor 78%, transparent));
  --happ-surface: var(--ac-surface, color-mix(in srgb, currentColor 3%, transparent));
  --happ-success: var(--ac-success, var(--success-color-medium, #27854d));
  --happ-warning: var(--ac-warning, var(--warn-color-medium, #a56700));
  --happ-link: var(--ac-accent, var(--link-color, #007ea8));
  color: var(--text-color-high, inherit);
  width: 100%; min-width: 0; font: inherit;
  container-type: inline-size;
}
.ac-happ, .ac-happ * { box-sizing: border-box; }
.ac-happ h3, .ac-happ h4, .ac-happ p { margin: 0; padding: 0; }
.ac-happ h3, .ac-happ h4 { font: inherit; font-weight: 600; border: 0; }
.ac-happ__toolbar, .ac-happ__profile-heading, .ac-happ__group-summary,
.ac-happ__resource-heading, .ac-happ__resource-identity, .ac-happ__source,
.ac-happ__rules-heading, .ac-happ__status { display: flex; align-items: center; gap: .5em; }
.ac-happ__toolbar { justify-content: space-between; gap: .75em; margin-bottom: .5em; }
.ac-happ .ac-happ__refresh {
  display: inline-flex; align-items: center; justify-content: center; gap: .35em;
  flex: 0 0 auto; font: inherit; white-space: nowrap;
}
.ac-happ .ac-happ__refresh:disabled { opacity: .6; cursor: wait; }
.ac-happ summary, .ac-happ a { border-radius: 4px; }
.ac-happ :is(button, summary, a):focus-visible { outline: 2px solid var(--happ-link); outline-offset: 3px; }
.ac-happ a { color: var(--happ-link); text-underline-offset: 3px; }
.ac-happ ::selection { background: var(--happ-link); color: Canvas; }
.ac-happ__icon { width: 1em; height: 1em; flex: 0 0 1em; vertical-align: middle; }
.ac-happ__muted, .ac-happ__count, .ac-happ__meta dt { color: var(--happ-muted); }
.ac-happ__notice {
  display: flex; align-items: baseline; flex-wrap: wrap; gap: .35em .75em;
  padding: .5em .75em; margin-bottom: .5em; border: 1px solid var(--happ-warning);
  border-radius: 5px; background: color-mix(in srgb, var(--happ-warning) 7%, transparent);
}
.ac-happ__notice > .ac-happ__icon { align-self: center; color: var(--happ-warning); }
.ac-happ__notice strong { font-weight: 600; }
.ac-happ__profile { margin: 0 0 .5em; border: 0; padding: 0; }
.ac-happ__profile > summary, .ac-happ__group > summary { list-style: none; cursor: pointer; }
.ac-happ__profile > summary::-webkit-details-marker, .ac-happ__group > summary::-webkit-details-marker { display: none; }
.ac-happ__profile > summary {
  display: block; padding: .5em .75em; border: 1px solid var(--happ-border);
  border-radius: 5px; background: var(--happ-surface);
}
.ac-happ__profile > summary:hover, .ac-happ__group > summary:hover { background: color-mix(in srgb, currentColor 6%, transparent); }
.ac-happ__profile-heading { flex-wrap: wrap; gap: .35em .75em; }
.ac-happ__profile-name { font-weight: 600; overflow-wrap: anywhere; }
.ac-happ__chevron { color: var(--happ-muted); transform: rotate(-90deg); }
.ac-happ__profile[open] > summary .ac-happ__chevron,
.ac-happ__group[open] > summary .ac-happ__chevron { transform: rotate(0); }
.ac-happ__meta { display: flex; flex-wrap: wrap; gap: .35em .75em; margin: .5em 0 0; }
.ac-happ__meta > div { display: flex; flex-wrap: wrap; align-items: baseline; gap: .25em .5em; min-width: 0; }
.ac-happ__meta dt, .ac-happ__meta dd { margin: 0; font-weight: 400; overflow-wrap: anywhere; }
.ac-happ__profile-body { padding-top: .5em; }
.ac-happ .ac-happ__message { padding: .5em .75em; overflow-wrap: anywhere; }
.ac-happ__message--warning { border: 1px solid var(--happ-warning); border-radius: 5px; margin-bottom: .5em !important; }
.ac-happ__rules-heading { flex-wrap: wrap; padding: 0 .75em .5em; gap: .35em .75em; }
.ac-happ__group { margin: 0 0 .5em; border: 1px solid var(--happ-border); border-radius: 5px; background: var(--happ-surface); }
.ac-happ__group-summary { padding: .5em .75em; gap: .5em; }
.ac-happ__group-label { font-weight: 600; }
.ac-happ__count { margin-left: auto; white-space: nowrap; font-variant-numeric: tabular-nums; }
.ac-happ__group-icon--direct { color: var(--happ-success); }
.ac-happ__group-icon--proxy { color: var(--happ-link); }
.ac-happ__group-icon--block { color: var(--error-color-medium, #d65353); }
.ac-happ__rule-columns { display: grid; grid-template-columns: minmax(0, 3fr) minmax(0, 2fr); padding: .5em .75em .5em 2.25em; border-top: 1px solid var(--happ-border); }
.ac-happ__rule-column { min-width: 0; }
.ac-happ__rule-column + .ac-happ__rule-column { border-left: 1px solid var(--happ-border); padding-left: .75em; margin-left: .75em; }
.ac-happ__rule-column h4 { margin-bottom: .35em; color: var(--happ-muted); }
.ac-happ .ac-happ__rule-list {
  padding: 0; margin: 0; border: 0; border-radius: 0; box-shadow: none;
  background: transparent; color: inherit; font: inherit;
  white-space: pre-wrap; overflow-wrap: anywhere; word-break: normal; max-height: 24rem; overflow-y: auto;
  scrollbar-color: var(--happ-border) transparent;
}
.ac-happ__resources { margin-top: .5em; border: 1px solid var(--happ-border); border-radius: 5px; background: var(--happ-surface); }
.ac-happ__resources > h4 { padding: .5em .75em; border-bottom: 1px solid var(--happ-border); }
.ac-happ__resource { padding: .5em .75em; }
.ac-happ__resource + .ac-happ__resource { border-top: 1px solid var(--happ-border); }
.ac-happ__resource-heading { flex-wrap: wrap; justify-content: space-between; gap: .35em .75em; }
.ac-happ__resource-identity { flex-wrap: wrap; gap: .35em .75em; }
.ac-happ__resource-name { font-weight: 600; }
.ac-happ__status { display: inline-flex; gap: .35em; }
.ac-happ__status--success { color: var(--happ-success); }
.ac-happ__status--warning { color: var(--happ-warning); }
.ac-happ__status--error { color: var(--error-color-medium, #d65353); }
.ac-happ__source { min-width: 0; gap: .35em .75em; flex-wrap: wrap; }
.ac-happ__source a { display: inline-flex; align-items: center; gap: .25em; white-space: nowrap; }
.ac-happ__source-name { overflow-wrap: anywhere; }
.ac-happ__resource .ac-happ__meta { margin-top: .35em; font-variant-numeric: tabular-nums; }
.ac-happ__resource > p { margin-top: .35em; }
.ac-happ__zones { margin-top: .5em; border: 1px solid var(--happ-border); border-radius: 5px; overflow: hidden; }
.ac-happ .ac-happ__zones table { width: 100%; table-layout: fixed; border: 0; border-collapse: collapse; margin: 0; font: inherit; }
.ac-happ .ac-happ__zones th, .ac-happ .ac-happ__zones td { padding: .35em .5em; text-align: left; vertical-align: top; border: 0; background: transparent; color: inherit; overflow-wrap: anywhere; }
.ac-happ .ac-happ__zones th { font-weight: 500; color: var(--happ-muted); background: var(--happ-surface); }
.ac-happ .ac-happ__zones td { border-top: 1px solid var(--happ-border); }
.ac-happ .ac-happ__zones th:first-child { width: 16%; }
@container (max-width: 640px) {
  .ac-happ__toolbar { align-items: flex-start; }
  .ac-happ__group-summary { flex-wrap: wrap; }
  .ac-happ__rule-columns { grid-template-columns: minmax(0, 1fr); padding: .5em .75em; gap: .75em; }
  .ac-happ__rule-column + .ac-happ__rule-column { border-left: 0; border-top: 1px solid var(--happ-border); padding: .5em 0 0; margin: 0; }
  .ac-happ__zones table, .ac-happ__zones tbody { display: block; }
  .ac-happ .ac-happ__zones thead { display: none; }
  .ac-happ .ac-happ__zones tr { display: block; padding: .35em 0; }
  .ac-happ .ac-happ__zones tr + tr { border-top: 1px solid var(--happ-border); }
  .ac-happ .ac-happ__zones td { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: .5em; border: 0; }
  .ac-happ__zones td::before { content: attr(data-label); color: var(--happ-muted); }
}
`;

// LuCI treats a scalar child as markup. Arrays always create safe text nodes.
function el(tag, attrs, children = []) {
  return E(tag, attrs, Array.isArray(children) ? children : [children]);
}

function svgEl(tag, attrs, children = []) {
  const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  children.forEach(child => node.appendChild(child));
  return node;
}

// Lucide's 24px outline geometry, rendered as namespaced DOM (never HTML).
function icon(name, className = "") {
  const paths = {
    chevron: ["m6 9 6 6 6-6"],
    refresh: ["M20 7v5h-5", "M4 17v-5h5", "M6.1 6.1a8 8 0 0 1 13.4 3M4.5 14.9a8 8 0 0 0 13.4 3"],
    direct: ["M5 12h14", "m12 5 7 7-7 7"],
    proxy: ["M4 7h16", "m16 3 4 4-4 4", "M20 17H4", "m8 13-4 4 4 4"],
    block: ["M9 9 15 15"],
    check: ["m9 12 2 2 4-4"],
    info: ["M12 16v-4", "M12 8h.01"],
    external: ["M7 17 17 7", "M7 7h10v10"],
    minus: ["M8 12h8"],
  };
  const round = ["block", "check", "info", "minus"].includes(name);
  return svgEl("svg", {
    xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none",
    stroke: "currentColor", "stroke-width": "1.8", "stroke-linecap": "round", "stroke-linejoin": "round",
    class: `ac-happ__icon ${className}`, "aria-hidden": "true", focusable: "false",
  }, [
    ...(round ? [svgEl("circle", { cx: "12", cy: "12", r: "9" })] : []),
    ...(paths[name] || []).map(d => svgEl("path", { d })),
  ]);
}

function statusLabel(value) {
  return {
    not_downloaded: _("Not downloaded"),
    not_required: _("Not required"),
    downloading: _("Downloading"),
    downloaded: _("Downloaded"),
    cached: _("Cached"),
    expired: _("Cache expired"),
    ready: _("Ready"),
    not_prepared: _("Not prepared"),
    interrupted: _("Download interrupted"),
    error: _("Error"),
  }[value] || _("Unknown");
}

function timestamp(value) {
  return value ? new Date(value * 1000).toLocaleString() : _("Not yet");
}

function errorLabel(value) {
  return {
    proxy_unavailable: _("The selected connection could not be prepared."),
    proxy_download_failed: _("Download through the selected connection failed. Direct fallback is disabled."),
    download_failed: _("Download failed."),
    invalid_file: _("The downloaded database is invalid."),
    cache_write_failed: _("Unable to save the database cache."),
    zone_invalid: _("The requested zone is missing or invalid in this database."),
  }[value] || value;
}

function groupLabel(name) {
  return { direct: _("Direct"), proxy: _("Proxy"), block: _("Block") }[name] || name;
}

function stateView(value, label = statusLabel(value)) {
  const success = ["ready", "cached", "downloaded", "selected"].includes(value);
  const warning = ["expired", "interrupted", "not_prepared"].includes(value);
  const tone = success ? "success" : value === "error" ? "error" : warning ? "warning" : "neutral";
  return el("span", { class: `ac-happ__status ac-happ__status--${tone}` }, [
    icon(success ? "check" : tone === "error" || warning ? "info" : "minus"), label,
  ]);
}

function metadata(items) {
  return el("dl", { class: "ac-happ__meta" }, items.map(([label, value]) =>
    el("div", {}, [el("dt", {}, label), el("dd", {}, value)]),
  ));
}

function sourceView(resource, key) {
  let url;
  try { url = new URL(resource.url); } catch (_error) { /* Keep malformed sources visible as text. */ }
  if (!url || !["http:", "https:"].includes(url.protocol))
    return el("span", { class: "ac-happ__source-name ac-happ__muted" }, resource.url || _("No source"));
  const segments = url.pathname.split("/").filter(Boolean);
  const name = url.hostname === "github.com" && segments.length >= 3
    ? `${segments[0]}/${segments[1]} · ${segments[segments.length - 1]}`
    : `${url.host}${url.pathname}`;
  return el("div", { class: "ac-happ__source" }, [
    el("a", { href: resource.url, target: "_blank", rel: "noopener noreferrer", title: resource.url,
      "aria-label": `${_("Source")}: ${resource.kind === "geoip" ? "GeoIP" : "GeoSite"}`,
      "data-focus-key": `${key}:source:${resource.kind}` }, [_("Source"), icon("external")]),
    el("span", { class: "ac-happ__source-name ac-happ__muted", title: resource.url }, name),
  ]);
}

function resourceView(resource, key) {
  const labels = [_("Zone"), _("Rule groups"), _("Saved configuration"), _("Preparation")];
  const zones = (resource.zones || []).map(zone => {
    const values = [zone.code, (zone.groups || []).map(groupLabel).join(", "), zone.configured ? _("Yes") : _("No"),
      el("span", {}, [stateView(zone.status), zone.error ? el("span", {}, `: ${errorLabel(zone.error)}`) : ""])];
    return el("tr", {}, values.map((value, index) => el("td", { "data-label": labels[index] }, value)));
  });
  const bytes = Number(resource.bytes) || 0;
  const size = bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MiB`
    : bytes >= 1024 ? `${(bytes / 1024).toFixed(1)} KiB` : `${bytes} B`;
  return el("section", { class: "ac-happ__resource", "aria-label": resource.kind === "geoip" ? "GeoIP" : "GeoSite" }, [
    el("div", { class: "ac-happ__resource-heading" }, [
      el("div", { class: "ac-happ__resource-identity" }, [
        el("span", { class: "ac-happ__resource-name" }, resource.kind === "geoip" ? "GeoIP" : "GeoSite"),
        stateView(resource.status),
        bytes > 0 ? el("span", { class: "ac-happ__muted", title: `${bytes} B` }, size) : "",
      ]), sourceView(resource, key),
    ]),
    resource.status !== "not_required" || resource.downloaded_at || resource.checked_at ? metadata([
      [_("Last successful download"), timestamp(resource.downloaded_at)],
      [_("Last check"), timestamp(resource.checked_at)],
    ]) : "",
    resource.error ? el("p", { class: "ac-happ__message ac-happ__message--warning", role: "alert" }, errorLabel(resource.error)) : "",
    zones.length ? el("div", { class: "ac-happ__zones" }, el("table", {}, [
      el("thead", {}, el("tr", {}, labels.map(label => el("th", { scope: "col" }, label)))),
      el("tbody", {}, zones),
    ])) : el("p", { class: "ac-happ__muted" }, _("This profile does not reference zones in this resource.")),
  ]);
}

function ruleGroup(profile, name, key) {
  const rules = (profile.rules || {})[name] || {};
  const sites = rules.sites || [], ips = rules.ips || [];
  const count = sites.length + ips.length;
  const groupKey = `${key}:${name}`;
  const columns = [[_("Domain rules"), sites], [_("IP rules"), ips]];
  return el("details", { class: "ac-happ__group", "data-happ-key": groupKey, ...(count ? { open: "" } : {}) }, [
    el("summary", { class: "ac-happ__group-summary", "data-focus-key": groupKey }, [
      icon("chevron", "ac-happ__chevron"), icon(name, `ac-happ__group-icon--${name}`),
      el("span", { class: "ac-happ__group-label" }, groupLabel(name)),
      count ? "" : el("span", { class: "ac-happ__muted" }, _("No rules")),
      el("span", { class: "ac-happ__count" }, `${count} ${_("rules")}`),
    ]),
    count ? el("div", { class: "ac-happ__rule-columns" }, columns.map(([label, values]) =>
      el("div", { class: "ac-happ__rule-column" }, [
        el("h4", {}, `${label} (${values.length})`),
        values.length ? el("pre", { class: "ac-happ__rule-list", tabindex: "0", "aria-label": label,
          "data-focus-key": `${groupKey}:${label}` }, values.join("\n"))
          : el("p", { class: "ac-happ__muted" }, _("No rules")),
      ]),
    )) : el("p", { class: "ac-happ__message ac-happ__muted" }, _("This action has no rules in the received profile.")),
  ]);
}

function renderStatus(data) {
  const route = data.download_via_proxy ? data.download_section || _("No connection selected") : _("Direct");
  const profiles = (data.profiles || []).map(profile => {
    const key = JSON.stringify([profile.section, profile.source_index]);
    const rules = Object.values(profile.rules || {});
    const siteCount = rules.reduce((total, group) => total + (group.sites || []).length, 0);
    const ipCount = rules.reduce((total, group) => total + (group.ips || []).length, 0);
    const order = profile.order ? profile.order.split("-").map(groupLabel).join(" → ") : _("Unknown");
    // Required resources come first; keep all other backend states visible.
    const resources = (profile.resources || []).slice().sort((a, b) =>
      Number(a.status === "not_required") - Number(b.status === "not_required"));
    return el("details", { class: "ac-happ__profile", "data-happ-key": key, ...(profile.selected ? { open: "" } : {}) }, [
      el("summary", { "data-focus-key": key }, [
        el("div", { class: "ac-happ__profile-heading" }, [
          icon("chevron", "ac-happ__chevron"), el("span", { class: "ac-happ__profile-name" }, profile.name || "HAPP"),
          stateView(profile.selected ? "selected" : "not_selected", profile.selected ? _("Selected") : _("Not selected")),
          el("span", { class: "ac-happ__muted" }, `${profile.label || profile.section} · #${profile.source_index}`),
        ]),
        metadata([[_("Download route"), route], [_("Rule order"), order], [_("Domain strategy"), profile.domain_strategy || _("Unknown")]]),
      ]),
      el("div", { class: "ac-happ__profile-body" }, [
        !profile.enabled ? el("p", { class: "ac-happ__message ac-happ__message--warning" }, _("HAPP routing is disabled in this subscription.")) : "",
        !profile.received_rules_known ? el("p", { class: "ac-happ__message ac-happ__message--warning" }, _("Cached normalized rules are shown. Refresh the subscription to show exactly which rules were received.")) : "",
        el("div", { class: "ac-happ__rules-heading" }, [
          el("h4", {}, _("Routing rules")),
          el("span", { class: "ac-happ__muted" }, `${siteCount} ${_("domain rules")} · ${ipCount} ${_("IP rules")}`),
        ]),
        ...["direct", "proxy", "block"].map(name => ruleGroup(profile, name, key)),
        resources.length ? el("section", { class: "ac-happ__resources", "aria-label": _("Resources") }, [
          el("h4", {}, _("Resources")), ...resources.map(resource => resourceView(resource, key)),
        ]) : "",
      ]),
    ]);
  });
  return el("div", { class: "ac-happ__content" }, [
    el("div", { class: "ac-happ__notice" }, [
      icon("info"), el("span", {}, _("Received subscription rules and saved runtime configuration.")),
      el("strong", {}, _("Apply changes to update the configured zones.")),
    ]),
    ...profiles,
    profiles.length ? "" : el("p", { class: "ac-happ__message ac-happ__muted" }, _("No HAPP routing profile is available in the current subscription cache.")),
  ]);
}

function createWidget() {
  const body = el("div", { class: "ac-happ__body" }, el("p", { class: "ac-happ__message", role: "status" }, _("Loading…")));
  let loading = false;
  let previous = "";
  const expanded = new Map();
  const scrolls = new Map();
  function rememberState() {
    if (!body.querySelectorAll) return;
    body.querySelectorAll("details[data-happ-key]").forEach(item => expanded.set(item.dataset.happKey, item.open));
    body.querySelectorAll(".ac-happ__rule-list").forEach(item => scrolls.set(item.dataset.focusKey, item.scrollTop));
  }
  async function refresh() {
    if (loading) return;
    loading = true;
    button.disabled = true;
    button.setAttribute("aria-busy", "true");
    try {
      rememberState();
      const response = await fs.exec("/usr/bin/anticheburnet", ["get_happ_status"]);
      if (response.code !== 0) throw new Error(_("Unable to load HAPP rules and resources."));
      if (response.stdout === previous) return;
      // A user may expand or scroll a group while the read is in flight.
      rememberState();
      const node = renderStatus(JSON.parse(response.stdout));
      if (body.querySelectorAll && node.querySelectorAll) {
        node.querySelectorAll("details[data-happ-key]").forEach(item => {
          if (expanded.has(item.dataset.happKey)) item.open = expanded.get(item.dataset.happKey);
        });
      }
      const focused = body.querySelector ? body.querySelector(":focus") : null;
      const focusKey = focused && focused.dataset.focusKey;
      body.replaceChildren(node);
      if (node.querySelectorAll) node.querySelectorAll(".ac-happ__rule-list").forEach(item => {
        if (scrolls.has(item.dataset.focusKey)) item.scrollTop = scrolls.get(item.dataset.focusKey);
      });
      if (focusKey) {
        const target = Array.from(node.querySelectorAll("[data-focus-key]")).find(item => item.dataset.focusKey === focusKey);
        if (target) target.focus({ preventScroll: true });
      }
      previous = response.stdout;
    } catch (_error) {
      rememberState();
      previous = "";
      body.replaceChildren(el("p", { class: "ac-happ__message ac-happ__message--warning", role: "alert" }, _("Unable to load HAPP rules and resources.")));
    } finally {
      loading = false;
      button.disabled = false;
      button.setAttribute("aria-busy", "false");
    }
  }
  const button = el("button", { class: "cbi-button ac-happ__refresh", type: "button", click: refresh }, [icon("refresh"), _("Refresh")]);
  const root = el("div", { class: "ac-happ" }, [
    el("style", {}, styles),
    el("div", { class: "ac-happ__toolbar" }, [el("h3", {}, _("HAPP rules and resources")), button]), body,
  ]);
  const tick = () => {
    if (!root.isConnected) { poll.remove(tick); return; }
    if (root.offsetParent === null) return;
    return refresh();
  };
  refresh();
  poll.add(tick, 5);
  return root;
}

return baseclass.extend({ createWidget, renderStatus, statusLabel });
