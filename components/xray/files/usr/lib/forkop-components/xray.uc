#!/usr/bin/ucode
let fs = require("fs");
let constants = require("singbox.constants");

function prepare(path) {
    let cfg = json(fs.readfile(path));
    if (type(cfg) != "object" || type(cfg.outbounds) != "array" || !length(cfg.outbounds))
        die("Xray config must contain a non-empty outbounds array\n");
    // Keep native Xray protocol settings, including fields introduced by 26.10.10.
    // The only managed ingress is local SOCKS; mark egress to avoid TPROXY recursion.
    cfg.inbounds = [{ tag: "forkop-socks", listen: "127.0.0.1", port: 10810,
        protocol: "socks", settings: { auth: "noauth", udp: true } }];
    for (let outbound in cfg.outbounds) {
        if (type(outbound) != "object" || type(outbound.protocol) != "string")
            die("Invalid native Xray outbound\n");
        if (type(outbound.streamSettings) != "object") outbound.streamSettings = {};
        if (type(outbound.streamSettings.sockopt) != "object") outbound.streamSettings.sockopt = {};
        outbound.streamSettings.sockopt.mark = constants.OUTBOUND_MARK;
    }
    return cfg;
}

if (ARGV[0] == "prepare") {
    let cfg = prepare(ARGV[1]);
    if (ARGV[2]) {
        if (fs.writefile(ARGV[2], sprintf("%J\n", cfg)) == null)
            die("Unable to write prepared Xray config\n");
        fs.chmod(ARGV[2], 0600);
    }
    else print(sprintf("%J\n", cfg));
}
else die("Usage: xray.uc prepare INPUT [OUTPUT]\n");
