#!/usr/bin/ucode
let fs = require("fs");
let ip = require("core.ip");
let constants = require("singbox.constants");

function prepare_text(text) {
    if (text == null) die("AWG config is unreadable\n");
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
            // DNS and traffic selection remain owned by Forkop. Never execute quick hooks.
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

function prepare(path) { return prepare_text(fs.readfile(path)); }

if (sourcepath(1) != null && sourcepath(1) != "")
    return { prepare, prepare_text };

if (ARGV[0] == "prepare") {
    let result = prepare(ARGV[1]);
    if (ARGV[2]) {
        if (fs.writefile(ARGV[2], result.device) == null) die("Unable to write AWG device config\n");
        fs.chmod(ARGV[2], 0600);
    }
    delete result.device;
    print(sprintf("%J\n", result));
}
else die("Usage: awg.uc prepare INPUT [DEVICE_OUTPUT]\n");
