#!/usr/bin/ucode
// Native profiles stay native; only their ingress and egress mark are managed.
let common = require("core.common");
let constants = require("singbox.constants");
const PORT_BASE = 10840;
const MAX_PROFILES = 8;

function config_error(config) {
    if (type(config) != "object" || type(config.outbounds) != "array" || !length(config.outbounds))
        return "Native Xray config must contain a non-empty outbounds array";
    if (length(sprintf("%J", config)) > 1048576) return "Native Xray config exceeds 1 MB";
    for (let outbound in config.outbounds)
        if (type(outbound) != "object" || type(outbound.protocol) != "string" || outbound.protocol == "")
            return "Invalid native Xray outbound";
    return "";
}

function prepare(config, port) {
    let error = config_error(config);
    if (error != "") die(error + "\n");
    if (port == null) port = 10810;
    if (type(port) != "int" || port < 1 || port > 65535) die("Invalid native Xray SOCKS port\n");
    config = json(sprintf("%J", config));
    config.inbounds = [{ tag: "anticheburnet-socks", listen: "127.0.0.1", port,
        protocol: "socks", settings: { auth: "noauth", udp: true } }];
    for (let outbound in config.outbounds) {
        if (type(outbound.streamSettings) != "object") outbound.streamSettings = {};
        if (type(outbound.streamSettings.sockopt) != "object") outbound.streamSettings.sockopt = {};
        outbound.streamSettings.sockopt.mark = constants.OUTBOUND_MARK;
    }
    return config;
}

function profile_error(outbound) {
    if (type(outbound) != "object" || outbound.type != "xray") return "Invalid native Xray profile";
    if (type(outbound.tag) != "string" || trim(outbound.tag) == "") return "Native Xray profile needs a tag";
    for (let key in keys(outbound))
        if (key != "type" && key != "tag" && key != "config")
            return "Native Xray profile accepts only type, tag and config; put Xray settings inside config";
    return config_error(outbound.config);
}

function prepare_outbounds(outbounds) {
    let profiles = [], seen = {};
    for (let outbound in outbounds) {
        if (outbound.type != "xray") continue;
        let error = profile_error(outbound);
        if (error != "") die(error + "\n");
        let serialized = sprintf("%J", outbound.config);
        let port = seen[serialized];
        if (port == null) {
            if (length(profiles) >= MAX_PROFILES) die("At most 8 distinct native Xray profiles are supported\n");
            port = PORT_BASE + length(profiles);
            seen[serialized] = port;
            push(profiles, { port, config: prepare(outbound.config, port) });
        }
        delete outbound.config;
        outbound.type = "socks";
        outbound.server = "127.0.0.1";
        outbound.server_port = port;
        outbound.version = "5";
    }
    return profiles;
}

function configured_outbounds(sections) {
    let result = [];
    for (let section in sections) {
        if (!common.bool_option(section, "enabled", true) ||
            index([ "connection", "proxy", "outbound", "vpn" ], common.option(section, "action", "")) < 0) continue;
        let items = section.outbound_jsons || section.outbound_json || [];
        if (type(items) != "array") items = [ items ];
        for (let item in items) {
            let value;
            try { value = json(item); } catch (error) { continue; }
            if (type(value) == "object" && value.type == "xray") push(result, value);
        }
    }
    return result;
}
function sections_require_native(sections) {
    return length(configured_outbounds(sections)) > 0;
}

function required() {
    let uci = require("core.uci");
    return sections_require_native(uci.section_objects("anticheburnet", "section")) ||
        common.bool_option(uci.get_all("anticheburnet_xray", "settings"), "enabled", false);
}

return { PORT_BASE, MAX_PROFILES, config_error, profile_error, prepare, prepare_outbounds,
    configured_outbounds, sections_require_native, required };
