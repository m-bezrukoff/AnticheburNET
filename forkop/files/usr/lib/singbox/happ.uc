let fs = require("fs");
let ip = require("core.ip");
let url = require("core.url");
let dns = require("singbox.dns");
let constants = require("singbox.constants");
let geodata = require("routing.geodata");

function merge(target, source) {
    for (let key, values in source) {
        if (target[key] == null) target[key] = [];
        for (let value in values) push(target[key], value);
    }
}

function matchers(group, profile, directory, data) {
    let sites = {}, ips = {};
    for (let item in group.sites) {
        let prefix = "", value = item, colon = index(item, ":");
        if (colon >= 0) { prefix = substr(item, 0, colon); value = substr(item, colon + 1); }
        if (prefix == "geosite") {
            if (data.geosite == null) data.geosite = geodata.load(profile.geosite_url, directory, "geosite");
            merge(sites, geodata.convert(data.geosite, "geosite", value));
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
            if (data.geoip == null) data.geoip = geodata.load(profile.geoip_url, directory, "geoip");
            merge(ips, geodata.convert(data.geoip, "geoip", substr(item, 6)));
        }
        else {
            if (!ip.valid_ip_or_cidr(item)) die("Invalid Happ IP rule\n");
            if (ips.ip_cidr == null) ips.ip_cidr = [];
            push(ips.ip_cidr, item);
        }
    }
    return { sites, ips };
}

function prepared(config, profile, tag, directory) {
    if (profile.fake_dns) die("Happ FakeDNS profiles currently require FakeDNS=false\n");
    let groups = {}, data = {};
    for (let kind in [ "block", "proxy", "direct" ]) groups[kind] = matchers(profile.rules[kind], profile, directory, data);
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
    let rule = length(keys(match)) ? { type: "logical", mode: "and", rules: [ scope, match ] } : { ...scope };
    for (let key, value in action) rule[key] = value;
    return rule;
}

function route_action(kind, tag) {
    return kind == "block" ? { action: "reject" } : { action: "route", outbound: kind == "direct" ? constants.DIRECT_OUTBOUND_TAG : tag };
}

function append_routes(config, policy, scope, tag) {
    let profile = policy.profile, order = split(profile.order, "-");
    if (profile.strategy == "IPOnDemand")
        push(config.route.rules, scoped(scope, {}, { action: "resolve", server: policy.remote }));
    for (let kind in order) {
        let group = policy.groups[kind], matches = [];
        if (length(keys(group.sites))) push(matches, group.sites);
        if (length(keys(group.ips))) push(matches, group.ips);
        if (!length(matches)) continue;
        let match = length(matches) == 1 ? matches[0] : { type: "logical", mode: "or", rules: matches };
        push(config.route.rules, scoped(scope, match, route_action(kind, tag)));
    }
    if (profile.strategy == "IPIfNonMatch") {
        push(config.route.rules, scoped(scope, {}, { action: "resolve", server: policy.remote }));
        for (let kind in order)
            if (length(keys(policy.groups[kind].ips)))
                push(config.route.rules, scoped(scope, policy.groups[kind].ips, route_action(kind, tag)));
    }
    push(config.route.rules, scoped(scope, {}, route_action(profile.global_proxy ? "proxy" : "direct", tag)));
}

function append_dns(config, policy, scope) {
    // Resolve DNS hosts locally, direct domains with DomesticDNS, and all other
    // domains with RemoteDNS through the section's selected proxy. GeoIP governs
    // traffic after resolution; it is not used as a DNS response filter.
    if (length(policy.host_names)) push(config.dns.rules, scoped(scope, { domain: policy.host_names }, { action: "route", server: policy.hosts }));
    for (let kind in split(policy.profile.order, "-")) {
        let sites = policy.groups[kind].sites;
        if (!length(keys(sites))) continue;
        let action = kind == "block" ? { action: "reject" } : { action: "route", server: kind == "direct" ? policy.domestic : policy.remote };
        push(config.dns.rules, scoped(scope, sites, action));
    }
    push(config.dns.rules, scoped(scope, {}, { action: "route", server: policy.profile.global_proxy ? policy.remote : policy.domestic }));
}

return { prepared, append_routes, append_dns };
