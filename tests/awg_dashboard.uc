let fs = require("fs");
let awg = require("core.awg");
let parser = require("subscription.parser");
let runtime = require("singbox.awg");
function check(value, message) { if (!value) die(message + "\n"); }
let key = b64enc("01234567890123456789012345678901");
let config = "[Interface]\nPrivateKey = " + key + "\nAddress = 10.7.0.2/32, fd00:7::2/128\n" +
    "Jc = 6\nH1 = 100-200\nHeaderProtectionKey = " + key + "\nRandomTrailers = on\n" +
    "DisableCookies = on\nContentPaddingAddition = 10\nRekeyAfterTime = 120\n" +
    "[Peer]\nPublicKey = " + key + "\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = vpn.example:443\n# AWG 3.1\n";
let link = "vpn://" + b64enc(config);
let profile = awg.parse_link(link);
check(profile.name == "AWG 3.1" && profile.config == config, "INI comment name and advanced fields must survive");
check(awg.parse_link(link + "#Renamed%20AWG").name == "Renamed AWG", "URI fragment must override the INI comment");
check(awg.parse_link("vpn://" + replace(replace(replace(b64enc(config), /\+/g, "-"), /\//g, "_"), /=/g, "")).config == config,
    "URL-safe unpadded base64 must work");
check(awg.parse_link("vpn://invalid!") == null, "Malformed base64 must not create an interface");
check(awg.parse_link("vpn://" + b64enc("compressed JSON is a different format")) == null, "Non-INI vpn containers must be rejected");
for (let suffix in [ "\nPreUp = malicious\n", "\n[Interface]\nAddress = 10.8.0.2/32\n" ]) {
    let rejected = false;
    try { awg.parse_link("vpn://" + b64enc(config + suffix)); } catch (error) { rejected = true; }
    check(rejected, "Hooks and repeated interfaces must be rejected");
}
let input = ARGV[0];
let output = ARGV[1];
check(fs.writefile(input, b64enc("vless://00000000-0000-4000-8000-000000000001@example.com:443#VLESS\n" +
    "hysteria2://password@example.com:443#Hysteria\n" + link + "\n")) != null, "Write mixed subscription");
check(parser.normalize_content_validated(input, output), "Mixed subscription normalization");
let normalized = json(fs.readfile(output));
check(length(normalized.outbounds) == 3 && normalized.skipped == 0, "All mixed subscription profiles must remain visible");
let nodes = normalized.outbounds;
let manifests = runtime.prepare_outbounds(nodes);
check(length(manifests) == 1 && manifests[0].config == config, "Native manifest must preserve the complete profile");
check(nodes[2].bind_interface == "acawg1" && nodes[2].__awg_config == null, "sing-box must bind to native AWG without private fields");
let multiple = [ { type: "direct", __awg_config: config }, { type: "direct", __awg_config: config },
    { type: "direct", __awg_config: replace(config, "10.7.0.2", "10.7.0.3") } ];
let distinct = runtime.prepare_outbounds(multiple);
check(length(distinct) == 2 && multiple[0].bind_interface == multiple[1].bind_interface &&
    multiple[2].bind_interface == "acawg2" && distinct[1].table == 313, "Deduplicate identical profiles and isolate distinct routing tables");
check(fs.writefile(output + ".awg.json", sprintf("%J", manifests)) != null, "Write native manifest");
check(length(runtime.profiles(output + ".awg.json")) == 1, "Validate native manifest");
check(fs.writefile(output + ".awg.json", '[{"interface":"wan","table":254,"config":""}]') != null, "Write invalid manifest");
let rejected = false;
try { runtime.profiles(output + ".awg.json"); } catch (error) { rejected = true; }
check(rejected, "Manifest must not bind to WAN or modify the main route table");
// Exercise lifecycle decisions with a private fake filesystem and intercepted
// service commands; never invoke a real init script from this test.
let fake = output + ".runtime";
fs.mkdir(fake);
fs.mkdir(fake + "/state");
fs.mkdir(fake + "/sockets");
fs.mkdir(fake + "/bin");
let source = fs.readfile(fs.dirname(sourcepath()) + "/../anticheburnet/files/usr/lib/singbox/awg.uc");
source = replace(source, "/etc/init.d/anticheburnet-awg-subscriptions", fake + "/service");
source = replace(source, /\/var\/run\/anticheburnet/g, fake + "/state");
source = replace(source, /\/var\/run\/amneziawg/g, fake + "/sockets");
source = replace(source, /\/usr\/bin/g, fake + "/bin");
fs.writefile(fake + "/test_awg.uc", source);
push(REQUIRE_SEARCH_PATH, fake + "/*.uc");
let owner = require("test_awg");
fs.writefile(fake + "/service", "");
fs.writefile(fake + "/bin/amneziawg-go", "");
fs.writefile(fake + "/bin/awg", "");
fs.writefile(output + ".awg.json", sprintf("%J", manifests));
let commands = [];
let command_status = 0;
let make_ready = true;
system = function(command) {
    push(commands, command);
    if (index(command, " restart") >= 0 && make_ready) {
        fs.writefile(fake + "/state/awg-acawg1.ready", "");
        fs.writefile(fake + "/sockets/acawg1.sock", "");
    }
    return command_status;
};
sleep = function(ms) {};
check(owner.sync(output + ".awg.json"), "Native runtime must start and wait for readiness");
check(length(commands) == 1, "First sync must restart the native service");
check(owner.sync(output + ".awg.json") && length(commands) == 1, "Unchanged ready runtime must not restart");
manifests[0].config = replace(config, "10.7.0.2", "10.7.0.4");
fs.writefile(output + ".awg.json", sprintf("%J", manifests));
check(owner.sync(output + ".awg.json") && length(commands) == 2, "Profile rotation must apply even when sing-box JSON is unchanged");
fs.writefile(output + ".awg.json", "[]");
check(owner.sync(output + ".awg.json") && length(commands) == 3, "Removing the last profile must stop the native runtime");
check(fs.readfile(fake + "/state/awg-subscriptions.json") == null, "Stopped runtime must remove its applied state");
fs.writefile(output + ".awg.json", sprintf("%J", manifests));
command_status = 1;
check(!owner.sync(output + ".awg.json"), "Service restart failure must abort readiness");
command_status = 0;
make_ready = false;
fs.unlink(fake + "/state/awg-acawg1.ready");
check(!owner.sync(output + ".awg.json"), "Unready tunnel must abort and stop its native service");
print("AWG vpn links, mixed subscription, names, advanced fields, isolation and rejection checks passed\n");
