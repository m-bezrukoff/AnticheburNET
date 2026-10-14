// Bind cached version output to the executable, including replacements by hand.
let fs = require("fs");
let file_cache = require("core.file_cache");
const DEFAULT_BINARY = getenv("ANTICHEBURNET_SING_BOX_BIN") || "/usr/bin/sing-box";
const DEFAULT_CACHE = getenv("ANTICHEBURNET_SING_BOX_VERSION_CACHE_FILE") ||
    (getenv("ANTICHEBURNET_RUNTIME_STATE_DIR") || "/var/run/anticheburnet") + "/core-version.json";

function signature(binary, cache_path) {
    let metadata = file_cache.identity(binary);
    if (metadata == null) return "";
    let digest = file_cache.digest(binary, cache_path + ".digest.json");
    return digest != "" ? metadata.signature + ":" + digest : "";
}

function cached(binary, cache_path) {
    binary ||= DEFAULT_BINARY;
    cache_path ||= DEFAULT_CACHE;
    let identity = signature(binary, cache_path);
    if (identity == "") return null;
    try {
        let value = json(fs.readfile(cache_path));
        if (value.signature == identity && type(value.version) == "string" && value.version != "" && type(value.output) == "string")
            return value;
    } catch (error) {}
    return null;
}

function ensure_parent(path) {
    let slash = rindex(path, "/");
    if (slash <= 0) return true;
    let parent = substr(path, 0, slash);
    if (fs.stat(parent) != null) return true;
    return ensure_parent(parent) && (fs.mkdir(parent, 0755) || fs.stat(parent) != null);
}

function get(binary, cache_path) {
    binary ||= DEFAULT_BINARY;
    cache_path ||= DEFAULT_CACHE;
    let value = cached(binary, cache_path);
    if (value != null) return value;
    let identity = signature(binary, cache_path);
    if (identity == "") return null;
    let quoted = "'" + replace(binary, /'/g, "'\\''") + "'";
    let pipe = fs.popen(quoted + " version 2>/dev/null", "r");
    if (!pipe) return null;
    let output = pipe.read("all"), status = pipe.close();
    // Do not associate a result with a binary replaced during the probe.
    if (status != 0 || output == null || signature(binary, cache_path) != identity) return null;
    let matched = match(output, /^sing-box version ([^\r\n ]+)/);
    if (matched == null) return null;
    value = { signature: identity, version: matched[1], output };
    if (ensure_parent(cache_path)) {
        let stamp = clock();
        let temporary = cache_path + "." + stamp[0] + "." + stamp[1];
        let file = fs.open(temporary, "w", 0600);
        if (file) {
            let written = file.write(sprintf("%J\n", value));
            file.close();
            if (written == null || !fs.rename(temporary, cache_path)) fs.unlink(temporary);
        }
    }
    return value;
}

return { cached, get };
