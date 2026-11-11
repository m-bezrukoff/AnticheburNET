function check(value, message) { if (!value) die(message); }
for (let alias in [ "chrome155", "chrome_155", "hellochrome_155", "HelloChrome_155" ])
    check(normalize_utls_fingerprint(alias) == "chrome155", "Chrome 155 fingerprint alias lost");
check(normalize_utls_fingerprint("hellochrome_133") == "chrome133", "explicit legacy Chrome fingerprint lost");
let original = {
    protocol: "vless", settings: {vnext:[{address:"example.com",port:443,users:[{id:"00000000-0000-4000-8000-000000000001",encryption:"none"}]}]},
    streamSettings: {network:"raw",security:"reality",realitySettings:{password:"new-key",publicKey:"old-key",shortId:"01",mldsa65Verify:"signature-key"}}
};
let converted = convert_xray_vless(original, "test");
check(converted.tls.reality.public_key == "new-key", "REALITY password alias or precedence lost");
check(converted.tls.reality.mldsa65_verify == "signature-key", "ML-DSA verification was silently dropped");
original.streamSettings = {network:"xdrive",security:"tls"};
check(convert_xray_vless(original, "test") == null, "XDRIVE silently became RAW");
check(!normalize_sing_box_json_value({outbounds:[original]}, "/rejected.json"), "unsupported Xray JSON fell back to sing-box JSON");
check(xray_skipped_configs([{outbounds:[original]}]) == 1, "unsupported Xray transport was not counted for the warning");
original.streamSettings = {network:"tcp",finalmask:{tcp:[{type:"noise"}]}};
check(convert_xray_vless(original, "test") == null, "unsupported finalmask silently disappeared");
original.streamSettings = {network:"xhttp",security:"tls",tlsSettings:{serverName:"upload.example"},xhttpSettings:{
    path:"/upload",mode:"packet-up",extra:{sessionPlacement:"header",sessionKey:"X-Session",xPaddingObfsMode:true,
        sessionIDTable:"hex",sessionIDLength:"16-24",noSSEHeader:true,scMaxBufferedPosts:12,
        downloadSettings:{address:"download.example",port:8443,security:"tls",tlsSettings:{serverName:"download-sni.example"},
            xhttpSettings:{path:"/download",extra:{sessionKey:"X-Download",xPaddingBytes:"200-400"}}}}}};
converted = convert_xray_vless(original, "test");
let t = converted.transport;
check(t.session_placement == "header" && t.session_key == "X-Session" && t.x_padding_obfs_mode === true, "XHTTP extra lost");
check(t.session_id_table == "hex" && t.session_id_length == "16-24" && t.no_sse_header && t.sc_max_buffered_posts == 12, "advanced XHTTP fields lost");
check(t.path == "/upload" && t.x_padding_bytes == "100-1000", "download settings replaced uplink");
check(t.download.server == "download.example" && t.download.server_port == 8443, "download endpoint lost");
check(t.download.tls.server_name == "download-sni.example" && t.download.path == "/download", "download TLS or path lost");
check(t.download.session_key == "X-Download" && t.download.x_padding_bytes == "200-400", "download extra lost");
original.streamSettings.xhttpSettings.mode = "stream-one";
check(convert_xray_vless(original, "test") == null, "invalid stream-one plus download was silently accepted");
let uri = "vless://00000000-0000-4000-8000-000000000001@example.com:443?security=reality&pbk=key&pqv=verify&type=raw";
converted = process_vless(uri, parse_url(uri));
check(converted.tls.reality.mldsa65_verify == "verify", "URI pqv lost");
uri = "vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&type=xdrive";
check(process_vless(uri, parse_url(uri)) == null, "unsupported URI transport accepted as TCP");
original.streamSettings = {network:"xhttp",security:"tls",xhttpSettings:{path:"/compat/",mode:"packet-up",
    extra:{uplinkHTTPMethod:"OPTIONS",h2Params:{MaxConcurrentStreams:64}}}};
converted = convert_xray_vless(original, "options-test");
check(converted.transport.uplink_http_method == "OPTIONS", "XHTTP OPTIONS method lost");
original.streamSettings = {network:"xdrive",security:"tls",xdriveSettings:{service:"s3",
    s3:{endpoint:"https://s3.example",bucket:"test",region:"test"}}};
check(convert_xray_vless(original, "s3-test") == null, "XDRIVE S3 silently became RAW");
check(index(xray_native_requirements([{outbounds:[original]}]), "XDRIVE") >= 0, "native XDRIVE requirement was not diagnosed");
let hints = {source_format:"xray-json",skipped:1,native_requirements:["XDRIVE","https://private-token.invalid"]};
let hints_path=temp_path("native-xray-hint-test");
fs.writefile(hints_path,sprintf("%J",hints));
let message=normalized_skipped_message(hints_path);
fs.unlink(hints_path);
check(index(message,"XDRIVE")>=0 && index(message,"private-token")<0,"native hint lost its reason or leaked untrusted metadata");
print("Xray password, ML-DSA, XHTTP split download and unsupported transport checks passed\n");
