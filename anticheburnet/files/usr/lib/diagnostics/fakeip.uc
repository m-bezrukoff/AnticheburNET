let common = require("core.common");
let constants = require("singbox.constants");

function shared_public_ip_expected(config) {
    config = common.object_or_empty(config);
    // Dynamic providers carry the current routing configuration separately.
    for (let provider in common.array_or_empty(config.providers))
        if (provider.type == "anticheburnet") {
            let payload = common.object_or_empty(common.read_json_file(provider.path));
            config = common.object_or_empty(payload.configuration);
            break;
        }

    let control_outbound = "";
    for (let rule in common.array_or_empty(common.object_or_empty(config.route).rules)) {
        if (type(rule) != "object" || (rule.action != null && rule.action != "route")) continue;
        let inbounds = type(rule.inbound) == "array" ? rule.inbound : [ rule.inbound ];
        if (index(inbounds, constants.TPROXY_INBOUND_TAG) < 0 ||
            index(inbounds, constants.TPROXY_INBOUND6_TAG) < 0) continue;
        if (rule.domain == constants.CHECK_PROXY_IP_DOMAIN && rule.outbound != null)
            control_outbound = rule.outbound;

        // HAPP and all-through-tunnel routing end in this unconditional rule.
        // A domain, source, port or other restriction is not a global fallback.
        let unconditional = true;
        for (let key in keys(rule))
            if (index([ "action", "inbound", "outbound" ], key) < 0)
                unconditional = false;
        if (unconditional)
            return control_outbound != "" && control_outbound != constants.DIRECT_OUTBOUND_TAG &&
                rule.outbound == control_outbound;
    }
    return false;
}

return { shared_public_ip_expected };
