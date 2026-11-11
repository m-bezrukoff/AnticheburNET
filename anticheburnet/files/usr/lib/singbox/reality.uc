// The extended 2.7.2 core can preserve the hybrid share required by Xray >= 26.9.8.
// Keep this option out of official and older extended cores, which reject it.
function supports_hybrid_share(version) {
    let matched = match(version || "", /extended-([0-9]+)[.]([0-9]+)[.]([0-9]+)/);
    if (matched == null)
        return false;
    let major = int(matched[1], 10);
    let minor = int(matched[2], 10);
    let patch = int(matched[3], 10);
    return major > 2 || (major == 2 && (minor > 7 || (minor == 7 && patch >= 2)));
}

function prepare_outbounds(outbounds, version) {
    let hybrid_supported = supports_hybrid_share(version);
    for (let outbound in outbounds || []) {
        let tls = outbound.tls;
        if (type(tls) == "object" && type(tls.utls) == "object" &&
            index([ "chrome155", "chrome_155", "hellochrome_155", "chrome133", "chrome_133", "hellochrome_133" ], tls.utls.fingerprint) >= 0) {
            let revision = match(version || "", /anticheburnet[.]([0-9]+)/);
            if (revision == null || int(revision[1]) < 8)
                die("Explicit Chrome 155/133 presets require sing-box component revision .8 or newer; update the complete release\n");
        }
        if (type(tls) != "object" || tls.enabled !== true ||
            type(tls.reality) != "object" || tls.reality.enabled !== true)
            continue;
        // Preserve the configured browser preset. The flag only keeps hybrid
        // shares already supplied by that preset; it cannot add missing shares.
        // The packaged uTLS includes current Chrome, Firefox and Safari presets
        // with X25519MLKEM768; the browser family still comes from the subscription.
        if (type(tls.utls) != "object")
            tls.utls = { enabled: true, fingerprint: "chrome" };
        else if (tls.utls.fingerprint == null || tls.utls.fingerprint == "") {
            tls.utls.fingerprint = "chrome";
            if (tls.utls.enabled == null)
                tls.utls.enabled = true;
        }
        // Explicit false keeps the classical handshake available for old servers.
        if (hybrid_supported && tls.reality.support_x25519mlkem768 !== false)
            tls.reality.support_x25519mlkem768 = true;
    }
}

return { supports_hybrid_share, prepare_outbounds };
