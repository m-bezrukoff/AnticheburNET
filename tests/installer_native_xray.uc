function check(value,message){if(!value)die(message+"\n");}
function as_string(value){return value==null?"":""+value;}
let sections=[],standalone="0";
function uci_get(path){return standalone;}
function uci_load(name){return true;}
function uci_cursor(){return{foreach:function(name,kind,callback){for(let section in sections)callback(section);}};}
// INSERT_INSTALLER_FUNCTION
check(!installer_xray_required(),"fresh install selected optional Xray");
let native=sprintf("%J",{type:"xray",tag:"native",config:{outbounds:[{protocol:"vless"}]}});
sections=[{enabled:"1",action:"connection",outbound_jsons:[native]}];
check(installer_xray_required(),"installer missed a configured native profile");
sections[0].enabled="false";
check(!installer_xray_required(),"disabled native profile selected optional Xray");
delete sections[0].enabled;sections[0].action="block";
check(!installer_xray_required(),"unused native profile selected optional Xray");
sections[0].action="connection";delete sections[0].outbound_jsons;sections[0].outbound_json=native;
check(installer_xray_required(),"installer missed the legacy singular JSON option");
sections=[];standalone="1";
check(installer_xray_required(),"enabled standalone Xray was not preserved");
print("Installer native Xray requirement selection passed\n");
