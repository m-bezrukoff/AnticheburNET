// Appended to singbox/generator.uc by the shell test, so this exercises the
// production generator and its version gate without UCI or a running router.
for (let version in [ "", "unknown", "1.13.18-extended-2.6.5", "1.14.0", "1.14.3-extended-2.7.3-anticheburnet.7", "2.0.0" ]) {
    runtime_sing_box_version = version;
    let modern = version == "1.14.0" || version == "1.14.3-extended-2.7.3-anticheburnet.7" || version == "2.0.0";
    for (let strategy in [ "selected", "happ", "tunnel" ]) {
        let config = base_config({ dns_server: "1.1.1.1", routing_strategy: strategy }, "127.0.0.1", {});
        let tproxy_count = 0;
        for (let inbound in config.inbounds) {
            if (inbound.type != "tproxy") {
                if (inbound.udp_mapping != null)
                    die("UDP mapping must only change transparent interception\n");
                continue;
            }
            tproxy_count++;
            if (modern && inbound.udp_mapping != "address_and_port_dependent")
                die("Each UDP peer address and port must get an independent routing decision\n");
            if (!modern && inbound.udp_mapping != null)
                die("Legacy and unknown cores must not receive unsupported UDP NAT fields\n");
        }
        if (tproxy_count != 2)
            die("UDP peer isolation must cover both IPv4 and IPv6\n");
        if (modern ? config.dns.independent_cache != null : config.dns.independent_cache !== true)
            die("The shared version gate must preserve DNS cache compatibility\n");
        let torrents = filter(config.route.rules, rule => rule.protocol == "bittorrent");
        if (length(torrents) != 1 || torrents[0].action != "route" || torrents[0].outbound != "direct-out")
            die("Detected BitTorrent must retain its direct route in every strategy\n");
    }
}
print("Torrent UDP mapping: IPv4/IPv6, three routing strategies and version compatibility passed\n");
