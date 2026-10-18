let fs = require("fs");
let ip = require("core.ip");
let url = require("core.url");
let dns = require("singbox.dns");
let constants = require("singbox.constants");
let geodata = require("routing.geodata");
let file_cache = require("core.file_cache");
const GEODATA_CONVERSION_CACHE_FORMAT = 1;

function file_digest(path) {
    return file_cache.digest(path, path + ".sha256.json");
}

function cached_ruleset(cache_path, directory, source_url, source_digest, selector) {
    let cached;
    try { cached = json(fs.readfile(cache_path)); } catch (error) { return null; }
    if (type(cached) != "object" || cached.format != GEODATA_CONVERSION_CACHE_FORMAT ||
        cached.source_url != source_url || cached.source_digest != source_digest ||
        cached.selector != selector ||
        !match(cached.ruleset_digest || "", /^[a-f0-9]{64}$/)) return null;
    let path = directory + "/" + cached.ruleset_digest + ".json";
    return file_digest(path) == cached.ruleset_digest ? path : null;
}

function remember_ruleset(cache_path, source_url, source_digest, ruleset_digest, selector) {
    let stamp = clock();
    let temporary = cache_path + "." + stamp[0] + "." + stamp[1];
    let file = fs.open(temporary, "w", 0600);
    if (!file) return;
    let written = file.write(sprintf("%J\n", {
        format: GEODATA_CONVERSION_CACHE_FORMAT, source_url, source_digest, ruleset_digest, selector
    }));
    file.close();
    if (written == null || !fs.rename(temporary, cache_path)) fs.unlink(temporary);
}

function merge(target, source) {
    for (let key, values in source) {
        if (target[key] == null) target[key] = [];
        for (let value in values) push(target[key], value);
    }
}

function geo_match(config, profile, directory, data, kind, code, tag) {
    if (!match(code, /^[A-Za-z0-9_@.-]+$/)) die("Unsupported Happ geodata tag\n");
    let key = kind + ":" + lc(code);
    if (data[key] != null) return { rule_set: [ data[key] ] };
    if (data[kind + "_path"] == null) data[kind + "_path"] = geodata.source_path(profile[kind + "_url"], directory, kind, data.download_options);
    if (data[kind + "_digest"] == null) data[kind + "_digest"] = file_digest(data[kind + "_path"]);
    let source_digest = data[kind + "_digest"];
    if (source_digest == "") die("Cannot identify Happ geodata source\n");
    let source_url = profile[kind + "_url"];
    let cache_key = replace(replace(b64enc(lc(code)), /\//g, "_"), /\+/g, "-");
    let cache_path = directory + "/converted-" + kind + "-" + cache_key + ".cache.json";
    let name = tag + "-happ-" + kind + "-" + b64enc(lc(code));
    let target = cached_ruleset(cache_path, directory, source_url, source_digest, key);
    if (target == null) {
        if (data[kind] == null) data[kind] = fs.readfile(data[kind + "_path"]);
        let converted;
        try { converted = geodata.convert(data[kind], kind, code); }
        catch (error) {
            geodata.resource_status(directory, "converted-" + kind + "-" + cache_key,
                { status: "error", url: source_url, code, checked_at: time(), error: "zone_invalid" });
            die("Happ geodata zone " + kind + ":" + code + " is missing or invalid\n");
        }
        let stamp = clock();
        let path = directory + "/converted." + stamp[0] + "." + stamp[1] + ".json";
        let output = fs.open(path, "w", 0600);
        if (!output) die("Cannot write RAM geodata ruleset\n");
        let written = output.write(sprintf("%J\n", { version: 3, rules: [ converted ] }));
        output.close();
        if (written == null) { fs.unlink(path); die("Cannot write RAM geodata ruleset\n"); }
        let digest = file_digest(path);
        if (digest == "") { fs.unlink(path); die("Cannot identify RAM geodata ruleset\n"); }
        target = directory + "/" + digest + ".json";
        if (!fs.rename(path, target)) die("Cannot install RAM geodata ruleset\n");
        remember_ruleset(cache_path, source_url, source_digest, digest, key);
    }
    push(config.route.rule_set, { type: "local", tag: name, format: "source", path: target });
    geodata.resource_status(directory, "converted-" + kind + "-" + cache_key,
        { status: "ready", url: source_url, code, checked_at: time(), path: target });
    data[key] = name;
    return { rule_set: [ name ] };
}

function matchers(config, group, profile, directory, data, tag) {
    let sites = {}, ips = {};
    for (let item in group.sites) {
        let prefix = "", value = item, colon = index(item, ":");
        if (colon >= 0) { prefix = substr(item, 0, colon); value = substr(item, colon + 1); }
        if (prefix == "geosite") {
            merge(sites, geo_match(config, profile, directory, data, "geosite", value, tag));
            continue;
        }
        let key = { "": "domain_keyword", domain: "domain_suffix", full: "domain", keyword: "domain_keyword", regexp: "domain_regex" }[prefix];
        if (key == null || value == "") die("Unsupported Happ domain rule\n");
        if (key == "domain_regex") regexp(value); // validate before applying any policy
        if (sites[key] == null) sites[key] = [];
        push(sites[key], value);
    }
    for (let item in group.ips) {
        if (index(item, "geoip:") == 0) {
            merge(ips, geo_match(config, profile, directory, data, "geoip", substr(item, 6), tag));
        }
        else {
            if (!ip.valid_ip_or_cidr(item)) die("Invalid Happ IP rule\n");
            if (ips.ip_cidr == null) ips.ip_cidr = [];
            push(ips.ip_cidr, item);
        }
    }
    return { sites, ips };
}

function prepared(config, profile, tag, directory, download_options) {
    if (profile.fake_dns) die("Happ FakeDNS profiles currently require FakeDNS=false\n");
    // Transparent router traffic arrives as IP packets. Keep the domain learned
    // by our DNS so domain rules also work when FakeDNS is disabled.
    config.dns.reverse_mapping = true;
    let groups = {}, data = { download_options };
    for (let kind in [ "block", "proxy", "direct" ]) groups[kind] = matchers(config, profile.rules[kind], profile, directory, data, tag);
    let predefined = {}, hosts = tag + "-happ-hosts", host_names = [];
    for (let name, value in profile.hosts) {
        let values = type(value) == "array" ? value : [ value ];
        for (let address in values) if (!ip.valid_ip(address)) die("Happ DnsHosts must contain IP addresses\n");
        predefined[name] = values;
        push(host_names, name);
    }
    let result = { profile, groups, hosts, host_names, remote: tag + "-happ-remote", domestic: tag + "-happ-domestic" };
    for (let kind in [ "remote", "domestic" ]) {
        let options = profile[kind + "_dns"];
        let transport = { DoH: "doh", DoT: "dot", DoU: "udp", DoQ: "quic" }[options.type];
        if (transport == null) die("Unsupported Happ DNS transport\n");
        if (!ip.valid_ip(options.ip)) die("Invalid Happ DNS bootstrap IP\n");
        let address = transport == "udp" ? options.ip : options.domain;
        let server;
        if (transport == "quic") server = { type: "quic", tag: result[kind], server: url.host(address), server_port: int(url.port(address) || 853) };
        else server = dns.server_from_options(result[kind], transport, address, kind == "remote" ? tag : constants.DIRECT_OUTBOUND_TAG);
        if (server.unsupported || !server.server) die("Invalid Happ DNS address\n");
        server.detour = kind == "remote" ? tag : constants.DIRECT_OUTBOUND_TAG;
        if (!ip.valid_ip(server.server)) {
            if (predefined[server.server] == null) predefined[server.server] = [ options.ip ];
            server.domain_resolver = hosts;
        }
        push(config.dns.servers, server);
    }
    push(config.dns.servers, { type: "hosts", tag: hosts, predefined });
    return result;
}

function scoped(scope, match, action) {
    // DNS generation removes inbound from its scope. Route rules must own their
    // scope, rather than retaining a reference to that subsequently changed object.
    let owned_scope = json(sprintf("%J", scope));
    let rule = !length(keys(owned_scope)) ? { ...match } :
        (length(keys(match)) ? { type: "logical", mode: "and", rules: [ owned_scope, match ] } : owned_scope);
    for (let key, value in action) rule[key] = value;
    return rule;
}

function route_action(kind, tag) {
    return kind == "block" ? { action: "reject" } : { action: "route", outbound: kind == "direct" ? constants.DIRECT_OUTBOUND_TAG : tag };
}

function append_routes(config, policy, scope, tag, direct_domains) {
    let profile = policy.profile, order = split(profile.order, "-");
    if (type(direct_domains) == "object" && length(keys(direct_domains))) {
        // Explicit local exclusions take priority over subscription policy.
        push(config.route.rules, scoped(scope, direct_domains, { action: "resolve" }));
        push(config.route.rules, scoped(scope, direct_domains, route_action("direct", tag)));
    }
    if (profile.strategy == "IPOnDemand")
        push(config.route.rules, scoped(scope, {}, { action: "resolve" }));
    for (let kind in order) {
        let group = policy.groups[kind], matches = [];
        if (length(keys(group.sites))) push(matches, group.sites);
        if (length(keys(group.ips))) push(matches, group.ips);
        if (!length(matches)) continue;
        let match = length(matches) == 1 ? matches[0] : { type: "logical", mode: "or", rules: matches };
        // Once a domain rule has selected its exit, resolve using that profile's
        // DNS rules before dialing. The global outbound resolver must not replace
        // DomesticDNS/RemoteDNS or bypass DnsHosts for this subscription.
        if (kind != "block" && profile.strategy != "IPOnDemand")
            push(config.route.rules, scoped(scope, match, { action: "resolve" }));
        push(config.route.rules, scoped(scope, match, route_action(kind, tag)));
    }
    if (profile.strategy == "IPIfNonMatch") {
        push(config.route.rules, scoped(scope, {}, { action: "resolve" }));
        for (let kind in order)
            if (length(keys(policy.groups[kind].ips)))
                push(config.route.rules, scoped(scope, policy.groups[kind].ips, route_action(kind, tag)));
    }
    // AsIs skips DNS while selecting an exit, but dialing the selected exit
    // still needs this profile's resolver, including its DnsHosts overrides.
    if (profile.strategy == "AsIs")
        push(config.route.rules, scoped(scope, {}, { action: "resolve" }));
    push(config.route.rules, scoped(scope, {}, route_action(profile.global_proxy ? "proxy" : "direct", tag)));
}

function append_dns(config, policy, scope, direct_domains) {
    // Resolve DNS hosts locally, direct domains with DomesticDNS, and all other
    // domains with RemoteDNS through the section's selected proxy. GeoIP governs
    // traffic after resolution; it is not used as a DNS response filter.
    if (length(policy.host_names)) push(config.dns.rules, scoped(scope, { domain: policy.host_names }, { action: "route", server: policy.hosts }));
    if (type(direct_domains) == "object" && length(keys(direct_domains)))
        push(config.dns.rules, scoped(scope, direct_domains, { action: "route", server: policy.domestic }));
    for (let kind in split(policy.profile.order, "-")) {
        let sites = policy.groups[kind].sites;
        if (!length(keys(sites))) continue;
        let action = kind == "block" ? { action: "reject" } : { action: "route", server: kind == "direct" ? policy.domestic : policy.remote };
        push(config.dns.rules, scoped(scope, sites, action));
    }
    push(config.dns.rules, scoped(scope, {}, { action: "route", server: policy.profile.global_proxy ? policy.remote : policy.domestic }));
}

return { prepared, append_routes, append_dns };
