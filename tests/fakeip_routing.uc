let fakeip = require("diagnostics.fakeip");
let fs = require("fs");
function check(value, message) { if (!value) die(message + "\n"); }
function config(outbound, extra) {
    return { route: { final: "direct-out", rules: [
        { action: "resolve", inbound: [ "tproxy-in", "tproxy6-in" ], domain: "ip.podkop.fyi", server: "dns-server" },
        { action: "route", inbound: [ "tproxy-in", "tproxy6-in" ], domain: "ip.podkop.fyi", outbound: "main-out" },
        { action: "route-options", domain: "fakeip.podkop.fyi", override_port: 8443 },
        { action: "route", inbound: [ "tproxy-in", "tproxy6-in" ], domain_suffix: [ "ru" ], outbound: "direct-out" },
        extra || { action: "route", inbound: [ "tproxy-in", "tproxy6-in" ], outbound }
    ] } };
}
check(fakeip.shared_public_ip_expected(config("main-out")), "HAPP tunnel fallback must allow a shared IP");
let tunnel = config("main-out");
splice(tunnel.route.rules, 3, 1);
check(fakeip.shared_public_ip_expected(tunnel), "All-through-tunnel must allow a shared IP");
check(!fakeip.shared_public_ip_expected(config("direct-out")), "Selective direct fallback must preserve warnings");
check(!fakeip.shared_public_ip_expected(config("backup-out")), "Different tunnel fallbacks must preserve warnings");
for (let restriction in [ { source_ip_cidr: [ "10.0.0.2/32" ] }, { port: 443 }, { domain_suffix: [ "example.com" ] } ]) {
    let rule = { action: "route", inbound: [ "tproxy-in", "tproxy6-in" ], outbound: "main-out" };
    for (let key, value in restriction) rule[key] = value;
    check(!fakeip.shared_public_ip_expected(config("main-out", rule)), "Restricted routes must not count as a global fallback");
}
check(!fakeip.shared_public_ip_expected({}), "Missing runtime configuration must preserve warnings");
let provider_path = ARGV[0];
fs.writefile(provider_path, sprintf("%J", { configuration: config("main-out") }));
check(fakeip.shared_public_ip_expected({ providers: [ { type: "anticheburnet", path: provider_path } ] }),
    "Dynamic provider routing must be inspected");
fs.writefile(provider_path, sprintf("%J", { configuration: config("direct-out") }));
check(!fakeip.shared_public_ip_expected({ route: config("main-out").route,
    providers: [ { type: "anticheburnet", path: provider_path } ] }), "Latest provider routing must override the root snapshot");
check(!fakeip.shared_public_ip_expected({ providers: [ { type: "anticheburnet", path: "/missing-provider.json" } ] }),
    "Unavailable provider configuration must preserve warnings");
print("FakeIP routing checks passed\n");
