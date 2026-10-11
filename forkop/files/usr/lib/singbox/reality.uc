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
    if (!supports_hybrid_share(version))
        return;

    for (let outbound in outbounds || []) {
        let tls = outbound.tls;
        if (type(tls) != "object" || tls.enabled !== true ||
            type(tls.reality) != "object" || tls.reality.enabled !== true)
            continue;
        // Explicit false keeps the classical handshake available for old servers.
        if (tls.reality.support_x25519mlkem768 === false)
            continue;
        tls.reality.support_x25519mlkem768 = true;
        // In the pinned uTLS, Chrome 133 carries ML-KEM before plain X25519.
        // Merely enabling the flag cannot add a share to older browser presets.
        if (type(tls.utls) == "object" && tls.utls.fingerprint != null &&
            tls.utls.fingerprint != "" && tls.utls.fingerprint != "chrome")
            warn("REALITY outbound '", outbound.tag || "", "': using chrome fingerprint for X25519MLKEM768\n");
        tls.utls = { enabled: true, fingerprint: "chrome" };
    }
}

return { supports_hybrid_share, prepare_outbounds };
