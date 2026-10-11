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

function geo_match(config, profile, directory, data, kind, code, tag) {
    if (!match(code, /^[A-Za-z0-9_@.-]+$/)) die("Unsupported Happ geodata tag\n");
    let key = kind + ":" + lc(code);
    if (data[key] != null) return { rule_set: [ data[key] ] };
    if (data[kind] == null) data[kind] = geodata.load(profile[kind + "_url"], directory, kind);
    let converted = geodata.convert(data[kind], kind, code);
    let name = tag + "-happ-" + kind + "-" + b64enc(lc(code));
    let path = directory + "/converted.json";
    if (fs.writefile(path, sprintf("%J\n", { version: 3, rules: [ converted ] })) == null)
        die("Cannot write RAM geodata ruleset\n");
    let pipe = fs.popen("sha256sum " + geodata.quote(path), "r");
    let digest = pipe ? substr(pipe.read("all") || "", 0, 64) : "";
    if (pipe) pipe.close();
    if (!match(digest, /^[a-f0-9]{64}$/)) die("Cannot identify RAM geodata ruleset\n");
    let target = directory + "/" + digest + ".json";
    if (!fs.rename(path, target)) die("Cannot install RAM geodata ruleset\n");
    push(config.route.rule_set, { type: "local", tag: name, format: "source", path: target });
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

function prepared(config, profile, tag, directory) {
    if (profile.fake_dns) die("Happ FakeDNS profiles currently require FakeDNS=false\n");
    let groups = {}, data = {};
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

function append_routes(config, policy, scope, tag) {
    let profile = policy.profile, order = split(profile.order, "-");
    if (profile.strategy == "IPOnDemand")
        push(config.route.rules, scoped(scope, {}, { action: "resolve" }));
    for (let kind in order) {
        let group = policy.groups[kind], matches = [];
        if (length(keys(group.sites))) push(matches, group.sites);
        if (length(keys(group.ips))) push(matches, group.ips);
        if (!length(matches)) continue;
        let match = length(matches) == 1 ? matches[0] : { type: "logical", mode: "or", rules: matches };
        push(config.route.rules, scoped(scope, match, route_action(kind, tag)));
    }
    if (profile.strategy == "IPIfNonMatch") {
        push(config.route.rules, scoped(scope, {}, { action: "resolve" }));
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
