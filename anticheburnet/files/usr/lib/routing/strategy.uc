let common = require("core.common");
let connections = require("config.connections");

function mode(settings) {
    return common.option(settings, "routing_strategy", "selected");
}

function global_tunnel(settings) {
    return mode(settings) == "happ" || mode(settings) == "tunnel";
}

function tunnel_section(settings, sections) {
    let requested = common.option(settings, "routing_section", "");
    for (let section in sections) {
        if (!common.bool_option(section, "enabled", true) ||
            !connections.is_connections_action(common.option(section, "action", ""))) continue;
        if (requested == "" || requested == section[".name"]) return section;
    }
    return null;
}

return { mode, global_tunnel, tunnel_section };
