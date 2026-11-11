#!/usr/bin/ucode
let fs = require("fs");
let native = require("core.xray");

function prepare(path) {
    return native.prepare(json(fs.readfile(path)), 10810);
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
