// Keep user-selected profiles across provider publication and service upgrades.
let fs = require("fs");
let common = require("core.common");
let as_string = common.as_string;
let object_or_empty = common.object_or_empty;
let array_or_empty = common.array_or_empty;
const LIB_DIR = getenv("ANTICHEBURNET_LIB") || "/usr/lib/anticheburnet";
const STATE_FILE = getenv("ANTICHEBURNET_SELECTOR_STATE_FILE") || "/etc/anticheburnet/selector-state.json";

function request(action, group, proxy) {
    let args = [ "ucode", "-L", LIB_DIR, LIB_DIR + "/diagnostics/runtime.uc", "clash-api", action ];
    if (group != null) push(args, group);
    if (proxy != null) push(args, proxy);
    let quoted = [];
    for (let arg in args) push(quoted, "'" + replace(as_string(arg), /'/g, "'\\''") + "'");
    let pipe = fs.popen(join(" ", quoted), "r");
    if (!pipe) return null;
    let output = pipe.read("all");
    if (pipe.close() != 0) return null;
    try { return json(output); } catch (e) { return null; }
}

function from_proxies(payload) {
    let result = {};
    for (let tag, proxy in object_or_empty(object_or_empty(payload).proxies)) {
        proxy = object_or_empty(proxy);
        let selected = as_string(proxy.now || "");
        if (lc(as_string(proxy.type)) == "selector" && selected != "" &&
            index(array_or_empty(proxy.all), selected) >= 0)
            result[tag] = selected;
    }
    return result;
}

function restore_pairs(snapshot, payload) {
    let result = [];
    let proxies = object_or_empty(object_or_empty(payload).proxies);
    for (let group, selected in object_or_empty(snapshot)) {
        let proxy = object_or_empty(proxies[group]);
        if (group != "" && type(selected) == "string" && selected != "" &&
            lc(as_string(proxy.type)) == "selector" &&
            index(array_or_empty(proxy.all), selected) >= 0 && proxy.now != selected)
            push(result, { group, proxy: selected });
    }
    return result;
}

function capture(api) {
    let payload = (api || request)("get_proxies");
    // An unavailable API must not erase the last saved selection during upgrade.
    return type(object_or_empty(payload).proxies) == "object" ? from_proxies(payload) : null;
}

function save(snapshot) {
    if (snapshot == null) return true;
    let parent = replace(STATE_FILE, /\/[^/]+$/, "");
    if (fs.stat(parent) == null && !fs.mkdir(parent, 0700)) return false;
    let temp = STATE_FILE + ".tmp";
    let file = fs.open(temp, "w", 0600);
    if (!file) return false;
    let data = sprintf("%J\n", snapshot);
    let ok = file.write(data) == length(data);
    file.close();
    return ok && fs.rename(temp, STATE_FILE);
}

function read() {
    return common.read_json_file(STATE_FILE);
}

function clear() {
    return fs.stat(STATE_FILE) == null || fs.unlink(STATE_FILE);
}

function restore(snapshot, api) {
    if (length(keys(object_or_empty(snapshot))) == 0) return true;
    api = api || request;
    let payload = api("get_proxies");
    if (type(object_or_empty(payload).proxies) != "object") return false;
    let ok = true;
    // A reachable API can still be loading provider groups. Do not consume the
    // handoff until every saved group is present. Removed members of a present
    // group may still fall back to that group's current default.
    for (let group, selected in object_or_empty(snapshot)) {
        if (lc(as_string(object_or_empty(payload.proxies[group]).type)) != "selector")
            ok = false;
    }
    for (let pair in restore_pairs(snapshot, payload)) {
        let result = api("set_group_proxy", pair.group, pair.proxy);
        if (!object_or_empty(result).success) ok = false;
    }
    return ok;
}

return { from_proxies, restore_pairs, capture, save, read, clear, restore };
