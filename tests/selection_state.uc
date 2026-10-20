let fs = require("fs");
let selection = require("singbox.selection");
function check(value, message) { if (!value) die(message + "\n"); }
let original = { proxies: {
    main: { type: "Selector", now: "chosen", all: ["first", "chosen"] },
    nested: { type: "Selector", now: "URLTest", all: ["first", "URLTest"] },
    auto: { type: "URLTest", now: "first", all: ["first"] },
    broken: { type: "Selector", now: "missing", all: ["first"] }
} };
let snapshot = selection.capture(function(action) { return original; });
check(snapshot.main == "chosen" && snapshot.nested == "URLTest" && length(keys(snapshot)) == 2,
    "Capture must keep valid manual choices including automatic groups chosen by the user");
check(selection.save(snapshot), "Selection must be saved before stopping for component replacement");
check(selection.capture(function(action) { return null; }) == null, "Unavailable API is not an empty selection");
check(selection.save(null) && selection.read().main == "chosen", "Repeated stop while offline must keep saved selection");
let updated = { proxies: {
    main: { type: "Selector", now: "new", all: ["new", "chosen", "first"] },
    nested: original.proxies.nested
} };
let calls = [];
check(selection.restore(selection.read(), function(action, group, proxy) {
    if (action == "get_proxies") return updated;
    push(calls, [group, proxy]);
    return { success: true };
}), "Selection restore must succeed after addition/reordering");
check(length(calls) == 1 && calls[0][0] == "main" && calls[0][1] == "chosen", "Only changed available profiles may be selected");
updated.proxies.main.all = ["new", "first"];
check(length(selection.restore_pairs(snapshot, updated)) == 0, "Removed profiles must fall back to an available default");
updated.proxies.main.all = ["chosen", "new"];
check(!selection.restore(snapshot, function(action) {
    return action == "get_proxies" ? updated : { success: false };
}), "Failed restore must be reported");
check(!selection.restore(snapshot, function(action) { return null; }), "Offline API must be reported");
check(!selection.restore(snapshot, function(action) { return { proxies: {} }; }),
    "API readiness without provider groups must not consume the saved selection");
check(!selection.restore(snapshot, function(action) {
    return { proxies: { main: updated.proxies.main } };
}), "Partially loaded provider groups must leave restoration pending");
check(selection.clear() && selection.read() == null, "Consumed handoff must not override newer choices on a later cold boot");
print("Selection capture, persistence, new profiles, reordering, missing profiles and API failures passed\n");
