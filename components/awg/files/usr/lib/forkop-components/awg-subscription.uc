#!/usr/bin/ucode
let fs = require("fs");
let parser = require("subscription.parser");
let awg = require("awg");
let happ = require("subscription.happ");

let fields = {
    jc: "Jc", jmin: "Jmin", jmax: "Jmax", s1: "S1", s2: "S2", s3: "S3", s4: "S4",
    h1: "H1", h2: "H2", h3: "H3", h4: "H4", i1: "I1", i2: "I2", i3: "I3", i4: "I4", i5: "I5",
    header_protection_key: "HeaderProtectionKey", content_padding_addition: "ContentPaddingAddition",
    rekey_after_time: "RekeyAfterTime", rekey_timeout: "RekeyTimeout", reject_after_time: "RejectAfterTime",
    keepalive_timeout: "KeepaliveTimeout", max_handshake_attempts: "MaxHandshakeAttempts",
    random_trailers: "RandomTrailers", disable_cookies: "DisableCookies"
};

function scalar(value) {
    if (type(value) == "bool") return value ? "on" : "off";
    if (type(value) == "array" && length(value) == 2) return scalar(value[0]) + "-" + scalar(value[1]);
    if (type(value) != "string" && type(value) != "int" && type(value) != "double")
        die("Invalid AWG subscription field type\n");
    value = trim("" + value);
    // Never let a value create another INI field, section, comment or shell hook.
    if (match(value, /[\r\n#]/) || index(value, chr(0)) >= 0) die("Invalid characters in AWG subscription field\n");
    return value;
}

function list_value(value) {
    if (type(value) == "array") return value;
    if (type(value) != "string") die("Invalid AWG address list\n");
    value = trim(value);
    if (substr(value, 0, 1) == "[") {
        if (substr(value, length(value) - 1) != "]") die("Invalid AWG address list\n");
        value = substr(value, 1, length(value) - 2);
    }
    let result = [];
    for (let item in split(value, ",")) {
        item = trim(item);
        if (match(item, /^['"].*['"]$/)) item = substr(item, 1, length(item) - 2);
        if (item != "") push(result, scalar(item));
    }
    return result;
}

function append(lines, key, value) {
    if (key == "RandomTrailers" || key == "DisableCookies") {
        if (value === true || value == "true" || value == "on" || value == "1") value = "on";
        else if (value === false || value == "false" || value == "off" || value == "0") value = "off";
        else if (value != null) die("Invalid AWG boolean option\n");
    }
    if (value != null && value != "") push(lines, key + " = " + scalar(value));
}

function endpoint(host, port) {
    host = scalar(host);
    if (substr(host, 0, 1) == "[" && substr(host, length(host) - 1) == "]") host = substr(host, 1, length(host) - 2);
    if (!match(host, /^[A-Za-z0-9_.:-]+$/) || !match("" + port, /^[0-9]+$/) || int(port) < 1 || int(port) > 65535)
        die("Invalid AWG peer endpoint\n");
    if (index(host, ":") >= 0 && substr(host, 0, 1) != "[") host = "[" + host + "]";
    return host + ":" + port;
}

function native_config(node) {
    let options = node.amnezia;
    if (type(options) != "object") return null;
    if (node.detour || node.bind_interface || node.system)
        die("AWG subscription detour, system and bind_interface options are not supported\n");
    let addresses = list_value(node.address || node.local_address);
    let lines = [ "[Interface]", "Address = " + join(", ", addresses) ];
    append(lines, "PrivateKey", node.private_key);
    append(lines, "MTU", node.mtu);
    append(lines, "ListenPort", node.listen_port);
    for (let key, value in options) {
        if (key == "version") {
            if ("" + value != "3" && "" + value != "3.1") die("Only AmneziaWG version 3/3.1 subscription options are supported\n");
            continue;
        }
        if (!fields[key]) die("Unsupported AmneziaWG subscription option\n");
        append(lines, fields[key], value);
    }
    let peers = node.peers;
    if (peers == null) peers = [{ address: node.server, port: node.server_port,
        public_key: node.peer_public_key, pre_shared_key: node.pre_shared_key,
        allowed_ips: node.allowed_ips || [ "0.0.0.0/0", "::/0" ] }];
    if (type(peers) != "array" || !length(peers)) die("AWG peers are required\n");
    for (let peer in peers) {
        if (type(peer) != "object") die("Invalid AWG peer\n");
        push(lines, "[Peer]");
        append(lines, "PublicKey", peer.public_key);
        append(lines, "PresharedKey", peer.pre_shared_key);
        append(lines, "Endpoint", endpoint(peer.address, peer.port));
        append(lines, "AllowedIPs", join(", ", list_value(peer.allowed_ips || [ "0.0.0.0/0", "::/0" ])));
        append(lines, "PersistentKeepalive", peer.persistent_keepalive_interval);
        if (peer.reserved != null) die("AWG subscription reserved bytes are not supported\n");
    }
    return join("\n", lines) + "\n";
}

function mihomo_config(record) {
    let options = {};
    for (let key, value in record) {
        if (index(key, "amnezia-wg-option.") != 0) continue;
        options[replace(substr(key, 18), /-/g, "_")] = value;
    }
    if (!length(options) || lc(record.type || "") != "wireguard") return null;
    if (record["dialer-proxy"] || record.reserved || record.peers)
        die("Mihomo AWG detour, reserved bytes and YAML multi-peer records are not supported\n");
    let addresses = [];
    for (let key in [ "ip", "ipv6" ]) {
        if (!record[key]) continue;
        let address = scalar(record[key]);
        if (index(address, "/") < 0) address += key == "ip" ? "/32" : "/128";
        push(addresses, address);
    }
    return native_config({ address: addresses, private_key: record["private-key"], mtu: record.mtu,
        amnezia: options, peers: [{ address: record.server, port: record.port,
            public_key: record["public-key"], pre_shared_key: record["pre-shared-key"],
            allowed_ips: list_value(record["allowed-ips"] || "0.0.0.0/0, ::/0"),
            persistent_keepalive_interval: record["persistent-keepalive"] }] });
}

function profiles(path) {
    let data = fs.readfile(path);
    if (data == null || length(data) > 1048576) die("AWG subscription is unreadable or exceeds 1 MB\n");
    data = trim(data);
    // Happ/ordinary subscriptions can wrap the complete body in base64.
    for (let depth = 0; depth < 2; depth++) {
        if (!match(data, /^[A-Za-z0-9+\/_=\s-]+$/)) break;
        let decoded = parser.base64_decode(data);
        if (decoded == null || decoded == data) break;
        data = trim(decoded);
    }
    if (substr(data, 0, 11) == "[Interface]") return [{ name: "AmneziaWG", config: data + "\n" }];
    let result = [];
    let value;
    try { value = json(data); } catch (error) { value = null; }
    if (value != null) {
        let candidates = type(value) == "array" ? value : [ value ];
        if (type(value) == "object") {
            if (type(value.endpoints) == "array" || type(value.outbounds) == "array")
                candidates = [ ...(value.endpoints || []), ...(value.outbounds || []) ];
            else if (type(value.proxies) == "array") candidates = value.proxies;
        }
        for (let node in candidates) {
            if (type(node) != "object") continue;
            let config;
            if (node.type == "wireguard" && type(node.amnezia) == "object") config = native_config(node);
            else if (node.type == "wireguard" && type(node["amnezia-wg-option"]) == "object") {
                let record = { ...node };
                for (let key, value in node["amnezia-wg-option"]) record["amnezia-wg-option." + key] = value;
                config = mihomo_config(record);
            }
            if (config) push(result, { name: "" + (node.tag || node.name || ("AmneziaWG " + (length(result) + 1))), config });
        }
    }
    else if (index(data, "proxies:") >= 0) {
        let records = parser.clash_yaml_records(null, data);
        for (let record in records) {
            let config = mihomo_config(record);
            if (config) push(result, { name: "" + (record.name || ("AmneziaWG " + (length(result) + 1))), config });
        }
    }
    return result;
}

let mode = ARGV[0];
if (mode == "url") {
    let source = parser.parse_subscription_source_entry(ARGV[1] || "");
    if (!source.valid || match(source.url, /\s/) || index(source.url, chr(0)) >= 0) die("Use an HTTP(S) subscription URL\n");
    print(source.url);
}
else if (mode == "private-key") {
    let prepared = awg.prepare(ARGV[1]);
    let key = match(prepared.device, /\nPrivateKey = ([^\n]+)/);
    if (!key) die("AWG private key is required\n");
    print(key[1], "\n");
}
else if (mode == "list" || mode == "extract") {
    parser.try_decode_gzip_content_file(ARGV[1]);
    let candidates = profiles(ARGV[1]);
    if (!length(candidates)) die("Subscription contains no supported AmneziaWG profiles\n");
    if (mode == "list") {
        let names = [];
        for (let candidate in candidates) push(names, candidate.name);
        print(sprintf("%J\n", names));
    }
    else {
        let selected = [];
        for (let candidate in candidates)
            if (ARGV[3] == null || ARGV[3] == "" || candidate.name == ARGV[3]) push(selected, candidate);
        if (length(selected) != 1) die("Select one unambiguous AWG profile by its exact name\n");
        awg.prepare_text(selected[0].config);
        let routing = happ.extract(ARGV[4] ? fs.readfile(ARGV[4]) : "", fs.readfile(ARGV[1]));
        if (routing != null)
            selected[0].config += "# Forkop-Happ-Routing = " + b64enc(sprintf("%J", routing)) + "\n";
        if (fs.writefile(ARGV[2], selected[0].config) == null) die("Unable to write AWG profile\n");
        fs.chmod(ARGV[2], 0600);
    }
}
else die("Usage: awg-subscription.uc url URL | list INPUT | extract INPUT OUTPUT [NAME]\n");
