#!/usr/bin/ucode
let fs = require("fs");
let awg = require("core.awg");
if (sourcepath(1) != null && sourcepath(1) != "") return awg;
if (ARGV[0] != "prepare") die("Usage: awg.uc prepare INPUT [DEVICE_OUTPUT]\n");
let result = awg.prepare(ARGV[1]);
if (ARGV[2]) {
    if (fs.writefile(ARGV[2], result.device) == null) die("Unable to write AWG device config\n");
    fs.chmod(ARGV[2], 0600);
}
delete result.device;
print(sprintf("%J\n", result));
