// Happ routing is subscription data, kept with the normalized nodes so a
// policy-only update has the same reload and rollback semantics as a node update.
let fs = require("fs");

function boolean(value, fallback) {
    if (value == null) return fallback;
    if (value === true || value == "true" || value == "1") return true;
    if (value === false || value == "false" || value == "0") return false;
    die("Invalid Happ routing boolean\n");
}

function decode(value) {
    value = replace(replace(value, /-/g, "+"), /_/g, "/");
    while (length(value) % 4) value += "=";
    try { return b64dec(value); } catch (error) { return null; }
}

function normalize(profile) {
    if (type(profile) != "object") die("Invalid Happ routing profile\n");
    let result = { enabled: true, name: profile.Name || "Happ",
        global_proxy: boolean(profile.GlobalProxy, true),
        order: profile.RouteOrder || "block-proxy-direct",
        strategy: profile.DomainStrategy || "IPIfNonMatch",
        fake_dns: boolean(profile.FakeDNS, false),
        last_updated: profile.LastUpdated || "",
        geoip_url: profile.Geoipurl || "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat",
        geosite_url: profile.Geositeurl || "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat",
        hosts: profile.DnsHosts || { "cloudflare-dns.com": "1.1.1.1", "dns.google": "8.8.8.8" }, rules: {} };
    if (!match(result.order, /^(block-proxy-direct|block-direct-proxy|proxy-block-direct|proxy-direct-block|direct-block-proxy|direct-proxy-block)$/))
        die("Unsupported Happ RouteOrder\n");
    if (index([ "AsIs", "IPIfNonMatch", "IPOnDemand" ], result.strategy) < 0)
        die("Unsupported Happ DomainStrategy\n");
    for (let kind in [ "Direct", "Proxy", "Block" ]) {
        let default_ips = kind == "Direct" ? [ "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "224.0.0.0/4", "255.255.255.255" ] : [];
        let group = { sites: profile[kind + "Sites"] || [], ips: profile[kind + "Ip"] || default_ips };
        for (let key in [ "sites", "ips" ]) {
            if (type(group[key]) != "array") die("Invalid Happ rule list\n");
            for (let item in group[key])
                if (type(item) != "string" || length(item) > 2048 || match(item, /[\r\n]/)) die("Invalid Happ rule\n");
        }
        result.rules[lc(kind)] = group;
    }
    if (type(result.hosts) != "object") die("Invalid Happ DNS hosts\n");
    for (let kind in [ "Remote", "Domestic" ])
        result[lc(kind) + "_dns"] = { type: profile[kind + "DNSType"] || "DoH",
            domain: profile[kind + "DNSDomain"] || (kind == "Remote" ? "https://cloudflare-dns.com/dns-query" : "https://dns.google/dns-query"),
            ip: profile[kind + "DNSIP"] || (kind == "Remote" ? "1.1.1.1" : "8.8.8.8") };
    return result;
}

function extract(headers, body) {
    let routing = "", enabled = null;
    for (let line in split(headers || "", "\n")) {
        line = trim(line);
        // curl -L writes every response's headers: only the final response applies.
        if (match(line, /^HTTP\//)) { routing = ""; enabled = null; }
        let colon = index(line, ":");
        if (colon < 1) continue;
        let key = lc(trim(substr(line, 0, colon))), value = trim(substr(line, colon + 1));
        if (key == "routing") routing = value;
        if (key == "routing-enable") enabled = boolean(value, true);
    }
    let candidates = routing == "" ? [] : [ routing ];
    for (let depth = 0; depth < 3; depth++) {
        for (let line in split(body || "", "\n")) {
            line = trim(line);
            if (index(line, "happ://routing/") == 0 && index(candidates, line) < 0) push(candidates, line);
        }
        if (!match(trim(body || ""), /^[A-Za-z0-9+\/_=\s-]+$/)) break;
        body = decode(body);
        if (body == null) break;
    }
    if (length(candidates) > 1) die("Multiple Happ routing profiles require separate subscription sections\n");
    if (enabled === false || candidates[0] == "happ://routing/off") return { enabled: false };
    if (!length(candidates)) return null;
    let found = match(candidates[0], /^happ:\/\/routing\/(add|onadd)\/(.+)$/);
    if (!found) die("Invalid Happ routing link\n");
    let text = decode(found[2]);
    if (text == null || length(text) > 262144) die("Invalid Happ routing payload\n");
    let profile;
    try { profile = json(text); } catch (error) { die("Invalid Happ routing JSON\n"); }
    return normalize(profile);
}

function attach(headers_path, body_path, normalized_path) {
    try {
        let profile = extract(fs.readfile(headers_path), fs.readfile(body_path));
        if (profile == null) return true;
        let subscription = json(fs.readfile(normalized_path));
        subscription.happ_routing = profile;
        return fs.writefile(normalized_path, sprintf("%J\n", subscription)) != null;
    } catch (error) {
        warn("Happ routing import failed; keeping the previous subscription\n");
        return false;
    }
}

return { normalize, extract, attach };
