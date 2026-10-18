let fs = require("fs");
let common = require("core.common");
let connections = require("config.connections");
let strategy = require("routing.strategy");
let subscription = require("singbox.subscription");
let constants = require("singbox.constants");

function zones(profile, kind) {
    let found = {};
    for (let group in [ "direct", "proxy", "block" ]) {
        let values = common.object_or_empty(common.object_or_empty(profile.rules)[group])[kind == "geoip" ? "ips" : "sites"] || [];
        for (let value in values) {
            let prefix = kind + ":";
            if (index(value, prefix) != 0) continue;
            let code = lc(substr(value, length(prefix)));
            if (found[code] == null) found[code] = [];
            if (index(found[code], group) < 0) push(found[code], group);
        }
    }
    return found;
}

function resource(section, profile, kind, config) {
    let directory = "/tmp/anticheburnet-happ-" + section;
    let url = profile[kind + "_url"];
    let selected_zones = zones(profile, kind);
    let result = { kind, url, status: length(keys(selected_zones)) ? "not_downloaded" : "not_required",
        zones: [], downloaded_at: 0, checked_at: 0, bytes: 0, error: "" };
    let saved = common.read_json_file(directory + "/" + kind + ".status.json");
    if (length(keys(selected_zones)) && !(type(saved) == "object" && saved.url == url)) {
        let cached = fs.stat(directory + "/" + kind + ".dat");
        if (cached != null && fs.readfile(directory + "/" + kind + ".dat.url") == url) {
            result.status = time() - cached.mtime < 604800 ? "cached" : "expired";
            result.downloaded_at = cached.mtime;
            result.bytes = cached.size;
        }
    }
    if (length(keys(selected_zones)) && type(saved) == "object" && saved.url == url) {
        for (let key in [ "status", "downloaded_at", "checked_at", "bytes", "error", "via_proxy", "proxy_section" ])
            if (saved[key] != null) result[key] = saved[key];
        if (result.status == "downloading" && time() - result.checked_at > 240)
            result.status = "interrupted";
    }
    for (let code, groups in selected_zones) {
        let encoded = replace(replace(b64enc(code), /\//g, "_"), /\+/g, "-");
        let state = common.read_json_file(directory + "/converted-" + kind + "-" + encoded + ".status.json");
        let converted = common.read_json_file(directory + "/converted-" + kind + "-" + encoded + ".cache.json");
        let zone = { code, groups, status: "not_prepared", configured: false, error: "" };
        let prepared_path = "";
        if (type(converted) == "object" && converted.source_url == url && match(converted.ruleset_digest || "", /^[a-f0-9]{64}$/)) {
            prepared_path = directory + "/" + converted.ruleset_digest + ".json";
            if (fs.stat(prepared_path) != null) zone.status = "ready";
        }
        if (type(state) == "object" && state.url == url) {
            zone.status = state.status;
            zone.error = state.error || "";
            if (state.path != null) prepared_path = state.path;
        }
        let expected_tag = constants.outbound_tag(section) + "-happ-" + kind + "-" + b64enc(code);
        for (let rule in common.array_or_empty(common.object_or_empty(config.route).rule_set))
            if (rule.tag == expected_tag && prepared_path == rule.path && fs.stat(rule.path) != null)
                zone.configured = true;
        push(result.zones, zone);
    }
    return result;
}

function snapshot(settings, sections, config) {
    settings = common.object_or_empty(settings);
    config = common.object_or_empty(config);
    // Subscription refreshes update the provider payload without rewriting the
    // root config. Its configuration is the latest saved routing snapshot.
    for (let provider in common.array_or_empty(config.providers))
        if (provider.type == "anticheburnet") {
            let payload = common.object_or_empty(common.read_json_file(provider.path));
            config = common.object_or_empty(payload.configuration);
            break;
        }
    let tunnel = strategy.tunnel_section(settings, sections);
    let result = { strategy: strategy.mode(settings), section: tunnel == null ? "" : tunnel[".name"], profiles: [],
        download_via_proxy: common.bool_option(settings, "download_lists_via_proxy", false),
        download_section: common.option(settings, "download_lists_via_proxy_section", "") };
    for (let section in sections) {
        if (!common.bool_option(section, "enabled", true) || !connections.is_connections_action(common.option(section, "action", ""))) continue;
        let index_value = 0;
        for (let entry in connections.subscription_urls(section)) {
            index_value++;
            let source = subscription.source_id(section[".name"], index_value);
            if (!subscription.source_cache_is_current(source, entry, connections.subscription_user_agent(section, entry),
                connections.subscription_hwid(section, entry), connections.subscription_device_headers_signature(section, entry))) continue;
            let profile = subscription.read_source_routing(source);
            if (type(profile) != "object") continue;
            let selected = result.strategy == "happ" && result.section == section[".name"] && profile.enabled;
            let item = { section: section[".name"], label: common.option(section, "label", section[".name"]),
                source_index: index_value, name: profile.name || "HAPP", enabled: !!profile.enabled, selected: !!selected,
                order: profile.order || "", domain_strategy: profile.strategy || "", rules: profile.received_rules || profile.rules || {},
                received_rules_known: profile.received_rules != null, resources: [] };
            if (profile.enabled)
                for (let kind in [ "geosite", "geoip" ])
                    push(item.resources, resource(section[".name"], profile, kind, config));
            push(result.profiles, item);
        }
    }
    return result;
}

return { snapshot, zones, resource };
