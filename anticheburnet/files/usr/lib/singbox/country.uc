#!/usr/bin/env ucode

let fs = require("fs");
let common = require("core.common");
let core_ip = require("core.ip");

let as_string = common.as_string;
let array_or_empty = common.array_or_empty;
let object_or_empty = common.object_or_empty;

const GEOIP_PREPARE = getenv("ANTICHEBURNET_GEOIP_PREPARE") || "/usr/bin/anticheburnet-geoip";
const GEOIP_SOURCE = getenv("ANTICHEBURNET_GEOIP_SOURCE") || "/usr/share/anticheburnet/geoip";

function shell_quote(value) {
    return "'" + replace(as_string(value), /'/g, "'\\''") + "'";
}

function command_from_args(args) {
    let parts = [];
    for (let arg in args)
        push(parts, shell_quote(arg));
    return join(" ", parts);
}

function command_output_from_args(args) {
    let pipe = fs.popen(command_from_args(args) + " 2>/dev/null", "r");
    if (!pipe)
        return "";

    let data = pipe.read("all");
    let status = pipe.close();
    if (status != 0 || data == null)
        return "";
    return as_string(data);
}

function valid_ipv4(value) {
    let parts = split(as_string(value), ".");
    if (length(parts) != 4)
        return false;
    for (let part in parts) {
        if (match(part, /^[0-9]+$/) == null || int(part, 10) < 0 || int(part, 10) > 255)
            return false;
    }
    return true;
}

function valid_ipv6(value) {
    return core_ip.valid_ipv6(value);
}

function public_ipv4(value) {
    if (!valid_ipv4(value))
        return false;

    let parts = split(value, ".");
    let a = int(parts[0], 10);
    let b = int(parts[1], 10);
    let c = int(parts[2], 10);

    if (a == 0 || a == 10 || a == 127 || a >= 224)
        return false;
    if (a == 100 && b >= 64 && b <= 127)
        return false;
    if (a == 169 && b == 254)
        return false;
    if (a == 172 && b >= 16 && b <= 31)
        return false;
    if (a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2))))
        return false;
    if (a == 198 && ((b == 18 || b == 19) || (b == 51 && c == 100)))
        return false;
    if (a == 203 && b == 0 && c == 113)
        return false;
    return true;
}

function public_ipv6(value) {
    if (!valid_ipv6(value))
        return false;

    value = lc(value);
    let first = split(value, ":")[0];
    if (match(first, /^[0-9a-f]{1,4}$/) == null)
        return false;
    let first_value = int(first, 16);
    if (first_value < 0x2000 || first_value > 0x3fff)
        return false;
    return match(value, /^2001:0?db8:/) == null;
}

function public_ip(value) {
    return public_ipv4(value) || public_ipv6(value);
}

function first_ipv4_line(value) {
    for (let line in split(as_string(value), "\n")) {
        line = trim(as_string(line));
        if (valid_ipv4(line))
            return line;
    }
    return "";
}

function first_ipv6_line(value) {
    for (let line in split(as_string(value), "\n")) {
        line = trim(as_string(line));
        if (valid_ipv6(line))
            return line;
    }
    return "";
}

function first_nslookup_address(value) {
    for (let line in split(as_string(value), "\n")) {
        line = trim(as_string(line));
        let matched = match(line, /^Address[ \t]*[0-9]*:[ \t]*([^ \t]+)$/);
        if (!matched)
            continue;

        let address = as_string(matched[1]);
        if (valid_ipv4(address) || valid_ipv6(address))
            return address;
    }
    return "";
}

function normalized_server(value) {
    value = lc(trim(as_string(value)));
    if (value != "" && substr(value, 0, 1) == "[" && substr(value, length(value) - 1) == "]")
        value = substr(value, 1, length(value) - 2);
    return value;
}

function normalized_resolver(value) {
    value = trim(as_string(value));
    // UCI list options are flattened by common.option(); use the first resolver.
    value = split(value, /[ \t]+/)[0];
    let separator = index(value, "#");
    if (separator >= 0)
        value = substr(value, 0, separator);
    if (substr(value, 0, 1) == "[" && substr(value, length(value) - 1) == "]")
        value = substr(value, 1, length(value) - 2);
    return valid_ipv4(value) || valid_ipv6(value) ? value : "";
}

function resolve_server(value, resolver) {
    let server = normalized_server(value);
    if (server == "")
        return "";
    if (valid_ipv4(server) || valid_ipv6(server))
        return server;
    if (index(server, ":") >= 0)
        return "";

    resolver = normalized_resolver(resolver);
    let args = [ "dig", "+short" ];
    if (resolver != "") push(args, "@" + resolver);
    push(args, server);
    let output = command_output_from_args([ ...args, "A", "+time=2", "+tries=1" ]);
    let address = first_ipv4_line(output);
    if (address == "") {
        output = command_output_from_args([ ...args, "AAAA", "+time=2", "+tries=1" ]);
        address = first_ipv6_line(output);
    }
    if (address != "")
        return address;

    // Do not fall back to the router's FakeIP resolver when a real resolver was given.
    return resolver == "" ? first_nslookup_address(command_output_from_args([ "nslookup", server ])) : "";
}

function database_revision() {
    return trim(as_string(fs.readfile(GEOIP_SOURCE + "/country.sha256")));
}

function lookup_ips(ips) {
    let result = {};
    if (length(ips) == 0) return result;
    let database = trim(command_output_from_args([ GEOIP_PREPARE ]));
    if (database == "" || substr(database, 0, 1) != "/" || fs.stat(database) == null) {
        warn("Local GeoIP database is unavailable; server countries were not detected\n");
        return result;
    }
    for (let ip in ips) {
        // mmdblookup returns a typed scalar, not JSON. Query only the ISO code.
        let output = command_output_from_args([ "mmdblookup", "--file", database, "--ip", ip, "country", "iso_code" ]);
        let matched = match(trim(output), /^"([A-Z]{2})"[ \t]+<utf8_string>$/);
        if (matched) result[ip] = matched[1];
    }
    return result;
}

function previous_countries_by_server(previous_state) {
    previous_state = object_or_empty(previous_state);
    let servers = object_or_empty(previous_state.servers);
    let countries = object_or_empty(object_or_empty(previous_state.outboundMetadata).countries);
    let result = {};

    for (let tag_name, server in servers) {
        let country = uc(as_string(countries[tag_name] || ""));
        server = normalized_server(server);
        if (server != "" && country != "")
            result[server] = country;
    }
    return result;
}

function detect(servers, previous_state, resolver) {
    servers = object_or_empty(servers);
    let cached = previous_countries_by_server(previous_state);
    let previous_revision = object_or_empty(object_or_empty(previous_state).outboundMetadata).countryDatabase;
    if (previous_revision != null && previous_revision != database_revision()) cached = {};
    let result = {};
    let pending_tags_by_server = {};
    let tags_by_ip = {};
    let ips = [];

    for (let tag_name, server in servers) {
        server = normalized_server(server);
        if (server == "")
            continue;
        if ((valid_ipv4(server) || valid_ipv6(server)) && !public_ip(server))
            continue;

        if (cached[server]) {
            result[tag_name] = cached[server];
            continue;
        }

        if (!pending_tags_by_server[server])
            pending_tags_by_server[server] = [];
        push(pending_tags_by_server[server], tag_name);
    }

    for (let server, tags in pending_tags_by_server) {
        let ip = resolve_server(server, resolver);
        if (!public_ip(ip))
            continue;
        if (!tags_by_ip[ip]) {
            tags_by_ip[ip] = [];
            push(ips, ip);
        }
        for (let tag_name in tags)
            push(tags_by_ip[ip], tag_name);
    }

    let countries_by_ip = lookup_ips(ips);
    for (let ip, tags in tags_by_ip) {
        let country = as_string(countries_by_ip[ip] || "");
        if (country == "")
            continue;
        for (let tag_name in tags)
            result[tag_name] = country;
    }

    return result;
}

return {
    detect,
    database_revision,
    normalized_server,
    public_ip,
    previous_countries_by_server
};
