let native = require("core.xray");
function check(value, message) { if (!value) die(message + "\n"); }
let config = { inbounds:[{listen:"0.0.0.0",port:443}], outbounds:[{tag:"proxy",protocol:"vless",
    settings:{vnext:[{address:"example.com",port:443,users:[{id:"00000000-0000-4000-8000-000000000001",encryption:"mlkem-test"}]}]},
    mux:{enabled:true,concurrency:128}, streamSettings:{network:"xdrive",security:"tls",
        tlsSettings:{serverName:"www.google.com",fingerprint:"hellochrome_155"},
        xdriveSettings:{service:"google-drive",secrets:["client-id","client-secret","private-test-token"],remoteFolder:"folder"},
        finalmask:{tcp:[{type:"fragment"}]},sockopt:{tcpFastOpen:true}}}],
    routing:{rules:[{type:"field",domain:["example.org"],outboundTag:"proxy"}]} };
let snapshot = sprintf("%J",config);
let outbounds = [{type:"xray",tag:"native-a",config}, {type:"xray",tag:"native-b",config}];
let profiles = native.prepare_outbounds(outbounds);
check(length(profiles)==1 && profiles[0].port==native.PORT_BASE,"identical native configs did not share an instance");
check(sprintf("%J",config)==snapshot,"native preparation mutated the source config");
check(outbounds[0].type=="socks" && outbounds[0].server=="127.0.0.1" && outbounds[0].server_port==outbounds[1].server_port,"native SOCKS bridge is invalid");
check(outbounds[0].config==null && outbounds[0].tag=="native-a","native secrets leaked into sing-box config or tag changed");
let prepared=profiles[0].config;
check(length(prepared.inbounds)==1 && prepared.inbounds[0].listen=="127.0.0.1" && prepared.inbounds[0].settings.udp,"native ingress was exposed or lost UDP");
check(prepared.outbounds[0].streamSettings.sockopt.mark==134217728 && prepared.outbounds[0].streamSettings.sockopt.tcpFastOpen,"native egress mark or original socket options lost");
for(let key in ["settings","mux"]) check(sprintf("%J",prepared.outbounds[0][key])==sprintf("%J",config.outbounds[0][key]),"native protocol setting lost");
for(let key in ["xdriveSettings","tlsSettings","finalmask"]) check(sprintf("%J",prepared.outbounds[0].streamSettings[key])==sprintf("%J",config.outbounds[0].streamSettings[key]),"native transport option lost");
check(sprintf("%J",prepared.routing)==sprintf("%J",config.routing),"native routing rules lost");
let enabled={enabled:"1",action:"connection",outbound_jsons:[sprintf("%J",{type:"xray",tag:"native",config})]};
check(native.sections_require_native([enabled]),"enabled native profile was not detected for updates");
enabled.enabled="0";
check(!native.sections_require_native([enabled]),"disabled profile selected the optional core");
enabled.enabled="1"; enabled.action="block";
check(!native.sections_require_native([enabled]),"unused native config selected the optional core");
check(native.profile_error({type:"xray",tag:"a",config:{outbounds:[]}})!="","empty native config accepted");
check(native.profile_error({type:"xray",tag:"a",config,detour:"remote"})!="","native bridge detour was silently accepted");
let many=[];
for(let i=0;i<=native.MAX_PROFILES;i++) push(many,{type:"xray",tag:"x"+i,config:{outbounds:[{protocol:"freedom",tag:"p"+i}]}});
let rejected=false;try{native.prepare_outbounds(many);}catch(error){rejected=true;}
check(rejected,"native instance limit was ignored");
print("Native Xray preservation, SOCKS bridge, update selection and limits passed\n");
let metadata = {outboundMetadata:{names:{},protocols:{},transports:{},securities:{}},servers:{}};
require("singbox.subscription").remember_outbound_metadata(metadata,"native","Native",{type:"xray",config});
check(metadata.outboundMetadata.protocols.native=="xray" && metadata.outboundMetadata.transports.native=="xdrive" && metadata.outboundMetadata.securities.native=="tls","native transport/security metadata describes the SOCKS bridge instead of the native connection");
check(index(sprintf("%J",metadata),"private-test-token")<0,"native credentials leaked into dashboard metadata");
