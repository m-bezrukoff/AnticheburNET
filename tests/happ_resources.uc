let geo = require("routing.geodata");
let status = require("routing.happ_status");
let sub_happ = require("subscription.happ");
let sub_runtime = require("singbox.subscription");
let fs = require("fs");
let work = ARGV[0];
let test_section = "resource_test" + replace(work, /[^A-Za-z0-9_]/g, "_");
let status_dir = "/tmp/anticheburnet-happ-" + test_section;
function check(value, label) { if (!value) die(label + "\n"); }
let options = geo.download_options({ download_lists_via_proxy: "1", download_lists_via_proxy_section: "chosen" });
check(options.proxy == "http://127.0.0.1:4534" && options.section == "chosen", "Configured list proxy must also be used by geodata");
check(geo.download_options({}).proxy == "", "Direct geodata must remain available when proxy is disabled");
let rejected = false;
try { geo.download_options({ download_lists_via_proxy: "1" }); } catch (e) { rejected = true; }
check(rejected, "Missing proxy selection must not silently download directly");
let requests = [], fail = false, invalid = false;
options.execute = function(command) {
    push(requests, command);
    if (fail) return 1;
    check(fs.writefile(work + "/geoip.dat.download", invalid ? "invalid" : chr(10) + chr(0)) != null, "Cannot write download fixture");
    return 0;
};
geo.source_path("https://one.test/geoip.dat", work, "geoip", options);
check(length(requests) == 1 && index(requests[0], "--proxy 'http://127.0.0.1:4534'") >= 0 &&
    index(requests[0], "--noproxy ''") >= 0 && index(requests[0], "curl -q") >= 0,
    "Geodata must pin explicit proxy routing and ignore ambient curl/proxy settings");
let saved = json(fs.readfile(work + "/geoip.status.json"));
check(saved.status == "downloaded" && saved.proxy_section == "chosen" && saved.bytes == 2, "Successful download status missing");
geo.source_path("https://one.test/geoip.dat", work, "geoip", options);
check(length(requests) == 1 && json(fs.readfile(work + "/geoip.status.json")).status == "cached", "Warm cache must avoid network downloads");
fail = true; rejected = false;
try { geo.source_path("https://two.test/geoip.dat", work, "geoip", options); } catch (e) { rejected = true; }
check(rejected && length(requests) == 2, "Failed proxy must not retry directly");
saved = json(fs.readfile(work + "/geoip.status.json"));
check(saved.status == "error" && saved.url == "https://two.test/geoip.dat", "Failed resource status must identify requested URL");
check(fs.readfile(work + "/geoip.dat.url") == "https://one.test/geoip.dat" && fs.readfile(work + "/geoip.dat") == chr(10) + chr(0), "Failure must preserve the last good database");
fail = false; invalid = true; rejected = false;
try { geo.source_path("https://two.test/geoip.dat", work, "geoip", options); } catch (e) { rejected = true; }
check(rejected && json(fs.readfile(work + "/geoip.status.json")).status == "error", "Invalid DAT must report an error");
check(fs.readfile(work + "/geoip.dat.url") == "https://one.test/geoip.dat", "Invalid DAT must not replace cache identity");
options.execute = function(command) { die("Unable to prepare native AWG for geodata download\n"); };
let proxy_error = "";
try { geo.source_path("https://two.test/geoip.dat", work, "geoip", options); }
catch (e) { proxy_error = e.message; }
check(index(proxy_error, "Unable to prepare native AWG for geodata download") >= 0,
    "Geodata preparation must preserve the underlying AWG failure");
let profile = sub_happ.normalize({ DirectIp: [ "geoip:RU" ], ProxySites: [ "geosite:youtube" ], BlockIp: [ "geoip:ru" ] });
check(length(status.zones(profile, "geoip").ru) == 2 && status.zones(profile, "geosite").youtube[0] == "proxy", "Resource zone selection must preserve all rule groups");
let implicit = sub_happ.normalize({});
check(length(implicit.received_rules.direct.ips) == 0 && length(implicit.rules.direct.ips) > 0, "Default private IP exclusions must not be mislabeled as received rules");
sub_runtime.source_cache_is_current = function() { return true; };
sub_runtime.read_source_routing = function() { return profile; };
let sections = [{ ".name": test_section, action: "connection", subscription_urls: [ "https://example.test/sub" ] }];
let snapshot = status.snapshot({ routing_strategy: "happ", routing_section: test_section }, sections, {});
check(length(snapshot.profiles) == 1 && snapshot.profiles[0].selected && snapshot.profiles[0].received_rules_known, "Selected incoming HAPP rules must be exposed");
check(!snapshot.profiles[0].resources[0].zones[0].configured, "Prepared rules must not be claimed as configured without a matching runtime ruleset");
check(!status.snapshot({ routing_strategy: "tunnel" }, sections, {}).profiles[0].selected, "Full tunnel must not claim HAPP rules are selected");
fs.mkdir(status_dir,0700);
fs.writefile(work+"/zone.json", "{}");
fs.writefile(status_dir+"/converted-geoip-cnU=.status.json",sprintf("%J",{
 status:"ready",url:profile.geoip_url,path:work+"/zone.json"
}));
let applied = {route:{rule_set:[{tag:test_section+"-out-happ-geoip-cnU=",path:work+"/zone.json"}]}};
check(status.resource(test_section,profile,"geoip",applied).zones[0].configured, "Only a matching existing configured ruleset can mark a zone as used");
fs.writefile(work+"/provider.json",sprintf("%J",{configuration:applied}));
let with_provider=status.snapshot({routing_strategy:"happ",routing_section:test_section},sections,{providers:[{type:"anticheburnet",path:work+"/provider.json"}]});
check(with_provider.profiles[0].resources[1].zones[0].configured,"Zone usage must follow refreshed provider configuration rather than the root config");
applied.route.rule_set[0].path=work+"/different.json";
check(!status.resource(test_section,profile,"geoip",applied).zones[0].configured, "A different saved ruleset must not be shown as applied");
let transport = require("routing.geodata_proxy");
let source_config = { route: { auto_detect_interface: true }, outbounds: [
 {type:"direct",tag:"direct-out"},
 {type:"selector",tag:"chosen-out",outbounds:["leaf"],default:"leaf"},
 {type:"socks",tag:"leaf",server:"127.0.0.1",server_port:1080,domain_resolver:"old-resolver"},
 {type:"socks",tag:"unrelated",server:"127.0.0.1",server_port:1082}
] };
let before = sprintf("%J",source_config);
let helper = transport.proxy_config(source_config,{},"chosen","1.14.1");
check(helper.config.route.final == "chosen-out" && length(helper.config.inbounds)==1 && helper.config.inbounds[0].listen=="127.0.0.1" && helper.config.inbounds[0].listen_port==0,
 "Bootstrap geodata proxy must be private and route through the selected connection");
check(length(helper.config.outbounds)==3 && helper.config.outbounds[2].domain_resolver=="bootstrap-dns-server", "Proxy must retain only selected dependencies and bootstrap DNS");
check(sprintf("%J",source_config)==before,"Preparing download proxy must not mutate the main configuration");
fs.writefile(work+"/helper.json",sprintf("%J",helper.config));
let started=0;
let result=transport.execute("curl --proxy 'http://127.0.0.1:4534' -- 'https://example.test/data'",options.proxy,source_config,{},"chosen",work,"1.14.1",function(command){
 started++;
 fs.writefile(work+"/proxy-command.txt",command);
 check(index(command,"$geodata_port")>=0 && index(command,"$geodata_pid")>=0 && index(command,"killall")<0,
  "Temporary proxy must use its own bound port and clean up only its own process");
 let paths=fs.glob(work+"/download-proxy-*.json");
 check(length(paths)==1 && json(fs.readfile(paths[0])).route.final=="chosen-out", "Private helper must exist before download");
 check((fs.stat(paths[0]).mode&0777)==0600,"Proxy credentials must be stored privately");
 return 17;
});
check(started==1 && result==17 && length(fs.glob(work+"/download-proxy-*.json"))==0,"Failed download must propagate status and remove private proxy configuration");
fs.unlink(status_dir+"/converted-geoip-cnU=.status.json");
fs.rmdir(status_dir);
print("HAPP proxy downloads, resource status and received rule checks passed\n");
