// Run the actual country owner with intercepted process boundaries. Any online
// geolocation call, unexpected command or private IP lookup fails this test.
function check(value, message) { if (!value) die(message + "\n"); }
let work = ARGV[0], calls = [], available = true;
fs.writefile(work + "/country.mmdb", "local database fixture");
database_revision = function() { return "local-generation-2"; };
command_output_from_args = function(args) {
    push(calls, args);
    if (args[0] == GEOIP_PREPARE) return available ? work + "/country.mmdb" : "";
    if (args[0] == "dig") {
        check(args[2] == "@9.9.9.9", "Domain lookup must use the configured real resolver");
        if (args[3] == "alpha.example" && args[4] == "A") return "8.8.8.8\n";
        if (args[3] == "beta.example" && args[4] == "AAAA") return "2606:4700:4700::1111\n";
        return "";
    }
    if (args[0] == "mmdblookup") {
        check(args[1] == "--file" && args[2] == work + "/country.mmdb", "Lookup must read the local database");
        check(args[3] == "--ip" && args[5] == "country" && args[6] == "iso_code", "Only the country scalar may be queried");
        check(public_ip(args[4]), "Private and reserved IPs must never be queried");
        if (args[4] == "8.8.8.8") return "\n  \"US\" <utf8_string>\n";
        if (args[4] == "2606:4700:4700::1111") return "\"AU\" <utf8_string>";
        if (args[4] == "9.9.9.9") return "\"<invalid>\" <utf8_string>";
        return "";
    }
    die("Unexpected external process: " + sprintf("%J", args) + "\n");
};
let servers = { alpha: "alpha.example", duplicate: "8.8.8.8", beta: "beta.example",
    unknown: "9.9.9.9", unresolved: "missing.example", private: "192.168.1.1",
    fakeip: "198.18.6.9", documentation: "203.0.113.10", loopback: "::1", private6: "fc00::1",
    invalid6: "2001:db8:::1", mappedPrivate: "::ffff:192.168.1.1" };
let detected = detect(servers, {}, "9.9.9.9 1.1.1.1");
check(detected.alpha == "US" && detected.duplicate == "US" && detected.beta == "AU", "IPv4 and IPv6 countries must map to every outbound tag");
check(length(keys(detected)) == 3, "Unknown, malformed, private and unresolved IPs must have no country");
let lookups = filter(calls, function(args) { return args[0] == "mmdblookup"; });
check(length(lookups) == 3, "Repeated IPs must be looked up once per batch");
check(!public_ip("2001:db8::1") && !public_ip("2001:db8:::1") && public_ip("2606:4700::1"), "IPv6 classification must reject invalid/reserved addresses");

calls = [];
let cached = detect({ renamed: "alpha.example" }, { servers: { old: "alpha.example" },
    outboundMetadata: { countries: { old: "DE" }, countryDatabase: "local-generation-2" } }, "9.9.9.9");
check(cached.renamed == "DE" && length(calls) == 0, "Warm cache must survive outbound renaming without any command");
let refreshed = detect({ renamed: "alpha.example" }, { servers: { old: "alpha.example" },
    outboundMetadata: { countries: { old: "DE" }, countryDatabase: "local-generation-1" } }, "9.9.9.9");
check(refreshed.renamed == "US", "A new local database generation must invalidate previous country values");

calls = []; available = false;
let absent = detect({ literal: "8.8.8.8" }, {}, "9.9.9.9");
check(length(keys(absent)) == 0 && length(calls) == 1 && calls[0][0] == GEOIP_PREPARE,
    "Missing database must never cause a DNS or online geolocation fallback for literal IPs");
print("Local country detection, caching and no-network-fallback checks passed\n");
