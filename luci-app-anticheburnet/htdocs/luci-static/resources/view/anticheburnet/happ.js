"use strict";
"require baseclass";
"require fs";
"require poll";

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
  return value ? new Date(value * 1000).toLocaleString() : "—";
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

function resourceView(resource) {
  const zones = (resource.zones || []).map((zone) =>
    E("tr", {}, [
      E("td", {}, zone.code),
      E("td", {}, zone.groups.join(", ")),
      E("td", {}, zone.configured ? _("Yes") : _("No")),
      E("td", {}, [statusLabel(zone.status), zone.error ? `: ${errorLabel(zone.error)}` : ""]),
    ]),
  );
  const url = /^https?:\/\//.test(resource.url || "")
    ? E("a", { href: resource.url, target: "_blank", rel: "noopener noreferrer" }, resource.url)
    : E("span", {}, resource.url || "—");
  return E("div", { class: "cbi-section" }, [
    E("h4", {}, resource.kind === "geoip" ? "GeoIP" : "GeoSite"),
    E("div", { style: "overflow-wrap:anywhere" }, url),
    E("p", {}, [
      statusLabel(resource.status),
      resource.bytes ? ` · ${resource.bytes} B` : "",
      " · ", _("Last successful download"), `: ${timestamp(resource.downloaded_at)}`,
      " · ", _("Last check"), `: ${timestamp(resource.checked_at)}`,
    ]),
    resource.error ? E("p", { class: "alert-message warning" }, errorLabel(resource.error)) : "",
    zones.length ? E("table", { class: "table" }, [
      E("tr", { class: "tr table-titles" }, [
        E("th", {}, _("Zone")), E("th", {}, _("Rule groups")),
        E("th", {}, _("In saved runtime configuration")), E("th", {}, _("Preparation")),
      ]), ...zones,
    ]) : E("p", {}, _("This profile does not reference zones in this resource.")),
  ]);
}

function renderStatus(data) {
  const profiles = (data.profiles || []).map((profile) => {
    const groups = ["direct", "proxy", "block"].map((name) => {
      const rules = profile.rules[name] || {};
      return E("tr", {}, [
        E("td", {}, name === "direct" ? "Direct" : name === "proxy" ? "Proxy" : "Block"),
        E("td", {}, E("pre", { style: "white-space:pre-wrap;overflow-wrap:anywhere" }, (rules.sites || []).join("\n") || "—")),
        E("td", {}, E("pre", { style: "white-space:pre-wrap;overflow-wrap:anywhere" }, (rules.ips || []).join("\n") || "—")),
      ]);
    });
    return E("details", { "data-profile": `${profile.section}:${profile.source_index}`, ...(profile.selected ? { open: "" } : {}) }, [
      E("summary", {}, `${profile.label} · ${profile.name} · #${profile.source_index} · ${profile.selected ? _("Selected") : _("Not selected")}`),
      E("p", {}, `${_("Rule order")}: ${profile.order || "—"} · ${_("Domain strategy")}: ${profile.domain_strategy || "—"}`),
      !profile.enabled ? E("p", {}, _("HAPP routing is disabled in this subscription.")) : "",
      !profile.received_rules_known ? E("p", {}, _("Cached normalized rules are shown. Refresh the subscription to show exactly which rules were received.")) : "",
      E("table", { class: "table" }, [
        E("tr", { class: "tr table-titles" }, [E("th", {}, _("Action")), E("th", {}, _("Domain rules")), E("th", {}, _("IP rules"))]),
        ...groups,
      ]),
      ...(profile.resources || []).map(resourceView),
    ]);
  });
  return E("div", {}, [
    E("p", {}, _("Received subscription rules and saved runtime configuration. Apply changes to update the configured zones.")),
    E("p", {}, `${_("Download route")}: ${data.download_via_proxy ? data.download_section || _("No connection selected") : _("Direct")}`),
    ...profiles,
    profiles.length ? "" : E("p", {}, _("No HAPP routing profile is available in the current subscription cache.")),
  ]);
}

function createWidget() {
  const body = E("div", {}, _("Loading…"));
  let loading = false;
  let previous = "";
  async function refresh() {
    if (loading) return;
    loading = true;
    try {
      const response = await fs.exec("/usr/bin/anticheburnet", ["get_happ_status"]);
      if (response.code !== 0) throw new Error(_("Unable to load HAPP rules and resources."));
      if (response.stdout === previous) return;
      const node = renderStatus(JSON.parse(response.stdout));
      if (body.querySelectorAll && node.querySelectorAll) {
        const expanded = new Map(Array.from(body.querySelectorAll("details[data-profile]"), item => [item.dataset.profile, item.open]));
        node.querySelectorAll("details[data-profile]").forEach(item => {
          if (expanded.has(item.dataset.profile)) item.open = expanded.get(item.dataset.profile);
        });
      }
      body.replaceChildren(node);
      previous = response.stdout;
    } catch (_error) {
      previous = "";
      body.replaceChildren(E("p", { class: "alert-message warning" }, _("Unable to load HAPP rules and resources.")));
    } finally {
      loading = false;
    }
  }
  const root = E("div", {}, [
    E("button", { class: "cbi-button", type: "button", click: refresh }, _("Refresh")), body,
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
