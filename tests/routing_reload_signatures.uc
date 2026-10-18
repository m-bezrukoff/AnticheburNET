// Appended to service/state.uc to exercise the actual Apply signatures.
function check(value, message) { if (!value) die(message + "\n"); }
let sections = [
    { ".name": "main", action: "connection", enabled: "1", connection_type: "proxy" },
    { ".name": "backup", action: "connection", enabled: "1", connection_type: "proxy" }
];
function signatures(settings) {
    return {
        singbox: sing_box_signature_body(settings, sections, [], false),
        nft: nft_runtime_signature_body(settings, sections)
    };
}
let previous = signatures({});
check(previous.singbox == signatures({ routing_strategy: "selected" }).singbox,
    "Legacy settings must use the selected strategy default");
for (let mode in [ "happ", "tunnel", "selected" ]) {
    let next = signatures({ routing_strategy: mode, routing_section: "main" });
    check(next.singbox != previous.singbox && next.nft != previous.nft,
        "Changing routing strategy must rebuild both sing-box and nftables");
    let switched = signatures({ routing_strategy: mode, routing_section: "backup" });
    check(next.singbox != switched.singbox && next.nft != switched.nft,
        "Changing tunnel section must rebuild both sing-box and nftables");
    previous = next;
}
print("Routing strategy and tunnel Apply signature checks passed\n");
