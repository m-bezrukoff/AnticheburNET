function check(value, message) { if (!value) die(message); }
let original_print = print;
let output = "";
print = function(...args) { for (let value in args) output += as_string(value); };
exit = function(status) { die("plan rejected: " + status); };
let release = {
    tag_name: "1.2.3", html_url: "release", assets: []
};
let names = [ "anticheburnet_1.2.3.apk", "luci-app-anticheburnet_1.2.3.apk",
    "sing-box-extended_1.14.1-extended-2.7.2-anticheburnet.3_openwrt_aarch64_cortex-a53.apk",
    "anticheburnet-xray_26.10.10-r1_aarch64_cortex-a53.apk",
    "anticheburnet-amneziawg_3.1.20260828-r4_aarch64_cortex-a53.apk" ];
for (let name in names) push(release.assets, { name, browser_download_url: "https://example/" + name });
read_stdin_json = function() { return release; };
anticheburnet_release_plan("1.2.3", "apk", "0", "aarch64_cortex-a53", "1");
let fields = split(replace(output, /\n$/, ""), "\t");
check(length(fields) == 13, "complete suite did not include all three cores");
check(fields[5] == "" && fields[6] == "", "translation became mandatory");
check(fields[7] == names[2] && fields[9] == names[3] && fields[11] == names[4], "wrong core assets");
function rejected(arch, ext, tag) {
    output = "";
    let failed = false;
    try { anticheburnet_release_plan(tag || "1.2.3", ext || "apk", "0", arch || "aarch64_cortex-a53", "1"); }
    catch (e) { failed = true; }
    check(failed && output == "", "invalid or incomplete suite plan accepted");
}
rejected("mips_24kc");
rejected(null, "ipk");
rejected(null, null, "1.2.4");
let saved = pop(release.assets);
rejected();
push(release.assets, saved, saved);
rejected();
pop(release.assets);
push(release.assets, release.assets[0]);
rejected();
pop(release.assets);
release.assets[2].browser_download_url = "";
rejected();
release.assets[2].browser_download_url = "https://example/" + names[2];
output = "";
anticheburnet_release_plan("1.2.3", "apk", "0", "", "0");
check(length(split(replace(output, /\n$/, ""), "\t")) == 7, "generic release plan changed");
original_print("Complete-suite asset selection checks passed\n");
