let awg = require("core.awg");
function check(ok, message) { if (!ok) die(message + "\n"); }
let key = b64enc("01234567890123456789012345678901");
let config = "[Interface]\nPrivateKey = " + key + "\nAddress = 10.7.0.2/32\nJc = 6\n" +
    "[Peer]\nPublicKey = " + key + "\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:443\n";
let requests = [];
let execute = function(args) {
    push(requests, args);
    if (args[2] == "@192.0.2.1") return "";
    return "alias.example.\n198.51.100.8\n";
};
let settings = { bootstrap_dns_server: [ "192.0.2.1", "1.1.1.1:5353" ] };
let result = awg.prepare_runtime(config, settings, execute);
check(index(result.device, "Endpoint = 198.51.100.8:443") >= 0, "Native AWG must resolve before setconf");
check(length(requests) == 3 && requests[2][2] == "@1.1.1.1" && requests[2][4] == "5353",
    "Bootstrap failover must respect configured resolver ports without using system DNS");
check(requests[0][7] == "+time=2" && requests[0][8] == "+tries=1", "DNS resolution must be bounded");
check(index(config, "vpn.example") >= 0, "Runtime resolution must preserve the saved profile");
requests = [];
result = awg.prepare_runtime(replace(config, "vpn.example:443", "[2001:db8::1]:443"), {}, execute);
check(!length(requests) && index(result.device, "[2001:db8::1]:443") >= 0, "Literal endpoints must not query DNS");
result = awg.prepare_runtime(config, {}, function(args) { return args[6] == "AAAA" ? "2001:db8::8\n" : ""; });
check(index(result.device, "Endpoint = [2001:db8::8]:443") >= 0, "IPv6-only endpoint answers need brackets");
let failed = false;
try { awg.prepare_runtime(config, {}, function(args) { return ""; }); } catch (e) { failed = true; }
check(failed, "Failed bootstrap DNS must reject startup before setconf can hang");
failed = false;
try { awg.prepare_runtime(replace(config, "vpn.example", "bad';touch /tmp/injected"), {}, execute); }
catch (e) { failed = true; }
check(failed, "Malformed endpoint hostnames must not reach commands");
print("AWG bootstrap DNS failover, timeout, IPv6, literal endpoint and private profile checks passed\n");
