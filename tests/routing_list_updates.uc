function check(value, message) {
    if (!value) die(message + "\n");
}
let section = { ".name": "main", action: "connection", community_lists: [ "ovh", "discord" ],
    domain_ip_lists: [ "https://example.com/old.lst" ], subscription_urls: [ "https://example.com/sub" ] };
check(has_list_update_sources([ section ]), "Saved lists must remain available for selected routing");
check(settings_update_interval({}) == "1d", "Default list update interval changed");
for (let strategy in [ "happ", "tunnel" ]) {
    let settings = { routing_strategy: strategy };
    check(settings_update_interval(settings) == "", "Global strategies must disable scheduled and due list updates");
    let plan = cron_refresh_plan_rows(settings, [ section ], "/usr/bin/anticheburnet", "# list", "# sub", "# component");
    check(plan.status == 0 && length(plan.rows) == 1 && index(plan.rows[0], "subscription\t") == 0,
        "Global strategies must retain subscription refresh and omit list refresh");
    uci_settings = function() { return settings; };
    list_update_pid_begin = function() { die("Ignored lists must not acquire an update lock\n"); };
    log_message = function(message, level) { check(level == "info", "Skipping unused lists must not report an error"); };
    exit = function(status) { die("skipped:" + status); };
    let skipped = false;
    try { list_update(); } catch (e) { skipped = index(e, "skipped:0") >= 0; }
    check(skipped, "Manual list refresh must skip before network or nft changes");
}
print("Global strategy list update checks passed\n");
