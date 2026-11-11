function check(value, message) { if (!value) die(message + "\n"); }
let files={},events=[], valid=true, started=true, save_ok=true;
fs.readfile=function(path){return files[path];};
fs.stat=function(path){return files[path]!=null || path==DIRECTORY || path==fs.dirname(DIRECTORY) ? {type:"file"}:null;};
fs.mkdir=function(path,mode){check(mode==0700,"native directory is not private");return true;};
fs.chmod=function(path,mode){check(mode==0700,"native directory mode changed");return true;};
fs.unlink=function(path){delete files[path];return true;};
fs.rename=function(from,to){if(!save_ok)return false;files[to]=files[from];delete files[from];return true;};
private_files.write_private=function(path,text){files[path]=text;return true;};
capture=function(args){
    if(args[0]==BINARY)return "Xray 26.11.9 test\n";
    if(args[0]==ASSETS)return "/assets\n";
    if(args[0]=="env"){push(events,"validate");return valid ? "ok":null;}
    die("Unexpected native command\n");
};
service_call=function(method,value){push(events,method);return true;};
wait_running=function(items){push(events,"ready");return started;};
let a=[{port:native.PORT_BASE,config:native.prepare({outbounds:[{protocol:"freedom",tag:"a"}]},native.PORT_BASE)}];
let b=[{port:native.PORT_BASE,config:native.prepare({outbounds:[{protocol:"freedom",tag:"b"}]},native.PORT_BASE)}];
files["/candidate"]=sprintf("%J",a);
check(sync("/candidate"),"native initial start failed");
check(events[0]=="validate" && index(events,"set")>0,"native process started before validation");
let saved_state=files[STATE],saved_config=files[config_path(a[0])];
events=[];check(sync("/candidate") && index(events,"set")<0,"unchanged native profile restarted");
files["/candidate"]=sprintf("%J",b); valid=false;events=[];
check(!sync("/candidate") && index(events,"set")<0 && files[STATE]==saved_state && files[config_path(a[0])]==saved_config,"invalid native config disrupted the running profile");
valid=true;started=false;events=[];
check(!sync("/candidate") && files[STATE]==saved_state && files[config_path(a[0])]==saved_config,"native startup failure did not restore the previous config");
check(length(filter(events,function(e){return e=="set";}))==2,"native rollback did not restore the previous process definition");
started=true;save_ok=false;events=[];
check(!sync("/candidate") && files[STATE]==saved_state && files[config_path(a[0])]==saved_config,"manifest failure was not rolled back");
save_ok=true;events=[];
check(sync("/candidate") && files[STATE]!=saved_state,"changed native profile was not published");
files["/candidate"]="[]";events=[];
check(sync("/candidate") && index(events,"delete")>=0 && files[STATE]==null,"removed native profile left its service running");
print("Native Xray validation, unchanged PID policy, rollback and removal checks passed\n");
