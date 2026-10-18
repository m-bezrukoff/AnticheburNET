#!/usr/bin/ucode
let fs = require("fs");
let ip = require("core.ip");
let constants = require("singbox.constants");

function prepare_text(text) {
    if (type(text) != "string" || length(text) > 1048576 || index(text, chr(0)) >= 0)
        die("AWG config is unreadable, invalid or exceeds 1 MB\n");
    let section = "";
    let addresses = [];
    let device = [];
    let seen = {};
    let mtu = 1376;
    let peers = 0;
    let interface_seen = false;
    let private_key_seen = false;
    // Pass AWG 3.1 fields verbatim to official awg, which validates their wire format.
    let interface_keys = [ "PrivateKey", "ListenPort", "Jc", "Jmin", "Jmax", "S1", "S2", "S3", "S4",
        "H1", "H2", "H3", "H4", "I1", "I2", "I3", "I4", "I5", "HeaderProtectionKey",
        "ContentPaddingAddition", "RekeyAfterTime", "RekeyTimeout", "RejectAfterTime",
        "KeepaliveTimeout", "MaxHandshakeAttempts", "RandomTrailers", "DisableCookies" ];
    let peer_keys = [ "PublicKey", "PresharedKey", "AllowedIPs", "Endpoint", "PersistentKeepalive", "AdvancedSecurity" ];
    for (let raw in split(text, "\n")) {
        let line = trim(replace(raw, /#.*$/, ""));
        if (line == "") continue;
        if (line == "[Interface]" || line == "[Peer]") {
            section = line;
            if (line == "[Interface]") {
                if (interface_seen || peers) die("Only one initial Interface section is supported\n");
                interface_seen = true;
            }
            else {
                if (!interface_seen || !private_key_seen) die("Interface PrivateKey is required before peers\n");
                if (peers && (!seen.PublicKey || !seen.AllowedIPs)) die("Peer PublicKey and AllowedIPs are required\n");
                peers++;
            }
            seen = {};
            push(device, line);
            if (line == "[Interface]") push(device, "FwMark = " + constants.OUTBOUND_MARK);
            continue;
        }
        let entry = match(line, /^([A-Za-z0-9]+)[ \t]*=[ \t]*(.*)$/);
        if (!entry || section == "") die("Invalid AWG config line\n");
        let key = entry[1], value = trim(entry[2]);
        if (seen[key]) die("Duplicate AWG config field: " + key + "\n");
        seen[key] = true;
        if (section == "[Interface]" && key == "Address") {
            for (let address in split(value, ",")) {
                address = trim(address);
                if (!ip.valid_ip_cidr(address)) die("Invalid AWG interface address\n");
                push(addresses, address);
            }
        }
        else if (section == "[Interface]" && key == "MTU") {
            if (!match(value, /^[0-9]+$/) || int(value) < 1280 || int(value) > 9000)
                die("AWG MTU must be between 1280 and 9000\n");
            mtu = int(value);
        }
        else if (section == "[Interface]" && (key == "DNS" || key == "Table" || key == "FwMark")) {
            // DNS and traffic selection remain owned by AnticheburNET. Never execute quick hooks.
        }
        else if (section == "[Peer]" && key == "AdvancedSecurity") {
            // Official Go 3.1 always uses AWG; tools' legacy per-peer flag is kernel-only.
            if (index([ "on", "true", "yes", "1" ], lc(value)) < 0)
                die("Userspace AWG 3.1 requires AdvancedSecurity=on; use a separate WireGuard interface for off\n");
        }
        else {
            let allowed = section == "[Interface]" ? interface_keys : peer_keys;
            if (index(allowed, key) < 0) die("Unsupported AWG field (hooks are forbidden): " + key + "\n");
            if (value == "") die("Empty AWG field: " + key + "\n");
            if (index([ "PrivateKey", "PublicKey", "PresharedKey", "HeaderProtectionKey" ], key) >= 0 &&
                (!match(value, /^[A-Za-z0-9+\/]{43}=$/) || length(b64dec(value)) != 32))
                die("Invalid 32-byte AWG key: " + key + "\n");
            if (key == "AllowedIPs") {
                for (let prefix in split(value, ","))
                    if (!ip.valid_ip_cidr(trim(prefix))) die("Invalid AWG AllowedIPs\n");
            }
            push(device, key + " = " + value);
            if (section == "[Interface]" && key == "PrivateKey") private_key_seen = true;
        }
    }
    if (!peers || !seen.PublicKey || !seen.AllowedIPs || !length(addresses))
        die("AWG Address, peer PublicKey and AllowedIPs are required\n");
    return { device: join("\n", device) + "\n", addresses, mtu };
}

// Resolve native AWG endpoints before awg setconf, independently of dnsmasq and
// the main sing-box instance. Use only the user's configured bootstrap servers.
function prepare_runtime(text, settings, execute) {
    let result = prepare_text(text);
    let dns = require("singbox.dns"), url = require("core.url");
    let query = type(execute) == "function" ? execute : function(args) {
        let quoted = [];
        for (let arg in args) push(quoted, "'" + replace(arg, /'/g, "'\\''") + "'");
        let pipe = fs.popen(join(" ", quoted) + " 2>/dev/null", "r");
        if (!pipe) return "";
        let output = pipe.read("all");
        return pipe.close() == 0 ? output : "";
    };
    let resolved = {}, lines = [];
    for (let line in split(result.device, "\n")) {
        let endpoint = match(line, /^Endpoint = (\[[^\]]+\]|[^:]+):([0-9]+)$/);
        if (endpoint == null) {
            if (index(line, "Endpoint = ") == 0) die("Invalid AWG endpoint\n");
            push(lines, line); continue;
        }
        let host = endpoint[1], port = int(endpoint[2]);
        if (port < 1 || port > 65535) die("Invalid AWG endpoint port\n");
        if (substr(host, 0, 1) == "[") host = substr(host, 1, length(host) - 2);
        if (ip.valid_ip(host)) { push(lines, line); continue; }
        if (!match(host, /^[A-Za-z0-9][A-Za-z0-9.-]*$/) || length(host) > 253)
            die("Invalid AWG endpoint hostname\n");
        if (resolved[host] == null) {
            let address = "";
            for (let server in dns.server_list(settings || {}, "bootstrap_dns_server", "77.88.8.8")) {
                let resolver = url.host(server), resolver_port = url.port(server) || "53";
                if (!ip.valid_ip(resolver) || !match(resolver_port, /^[0-9]+$/) ||
                    int(resolver_port) < 1 || int(resolver_port) > 65535) continue;
                for (let family in [ "A", "AAAA" ]) {
                    let output = query([ "dig", "+short", "@" + resolver, "-p", resolver_port, host, family,
                        "+time=2", "+tries=1" ]);
                    for (let value in split(output || "", "\n"))
                        if (ip.valid_ip(trim(value))) { address = trim(value); break; }
                    if (address != "") break;
                }
                if (address != "") break;
            }
            if (address == "") die("Unable to resolve AWG endpoint through configured bootstrap DNS\n");
            resolved[host] = address;
        }
        let address = resolved[host];
        push(lines, "Endpoint = " + (index(address, ":") >= 0 ? "[" + address + "]" : address) + ":" + endpoint[2]);
    }
    result.device = join("\n", lines);
    return result;
}

function prepare(path) { return prepare_text(fs.readfile(path)); }

// This provider's vpn:// links contain a plain INI profile in base64, rather
// than the compressed JSON container used by the Amnezia application.
function parse_link(link) {
    if (substr(link, 0, 6) != "vpn://" || length(link) > 1048576) return null;
    let encoded = substr(link, 6);
    let name = "";
    let fragment = index(encoded, "#");
    if (fragment >= 0) {
        name = substr(encoded, fragment + 1);
        encoded = substr(encoded, 0, fragment);
        name = replace(name, /%([0-9a-fA-F]{2})/g, function(m, hex) { return chr(int(hex, 16)); });
    }
    if (!match(encoded, /^[A-Za-z0-9+\/_-]+={0,2}$/)) return null;
    encoded = replace(replace(encoded, /-/g, "+"), /_/g, "/");
    while (length(encoded) % 4) encoded += "=";
    let config = b64dec(encoded);
    if (config == null || index(config, chr(0)) >= 0) return null;
    config = trim(config);
    if (substr(config, 0, 11) != "[Interface]" ||
        !match(config, /\n[ \t]*(Jc|H1|HeaderProtectionKey)[ \t]*=/)) return null;
    prepare_text(config);
    if (name == "") {
        for (let line in split(config, "\n")) {
            let comment = match(trim(line), /^#[ \t]*(.+)$/);
            if (comment) name = comment[1];
        }
    }
    let clean_name = "";
    for (let i = 0; i < length(name); i++) {
        let char = substr(name, i, 1);
        clean_name += ord(char) < 32 || ord(char) == 127 ? " " : char;
    }
    name = trim(clean_name);
    return { name: substr(name || "AmneziaWG", 0, 200), config: config + "\n" };
}

if (sourcepath(1) != null && sourcepath(1) != "")
    return { prepare, prepare_text, prepare_runtime, parse_link };

if (ARGV[0] == "prepare" || ARGV[0] == "prepare-runtime") {
    let result = ARGV[0] == "prepare-runtime" ?
        prepare_runtime(fs.readfile(ARGV[1]), require("core.uci").get_all("anticheburnet", "settings")) : prepare(ARGV[1]);
    if (ARGV[2]) {
        if (fs.writefile(ARGV[2], result.device) == null) die("Unable to write AWG device config\n");
        fs.chmod(ARGV[2], 0600);
    }
    delete result.device;
    print(sprintf("%J\n", result));
}
else die("Usage: awg.uc prepare|prepare-runtime INPUT [DEVICE_OUTPUT]\n");
