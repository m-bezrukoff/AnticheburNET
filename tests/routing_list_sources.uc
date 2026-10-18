function check(value, message) {
    if (!value) die(message + "\n");
}
let sections = [ { ".name": "main", action: "connection", community_lists: [ "ovh" ],
    domain_ip_lists: [ "https://example.com/old.lst" ] } ];
let saved = sprintf("%J", sections);
for (let settings in [ {}, { routing_strategy: "selected" } ]) {
    check(has_list_update_sources_from_sections(sections, settings), "Selected routing must detect saved lists");
    check(has_nft_list_update_sources_from_sections(sections, settings), "Selected routing must import saved subnet lists");
}
for (let strategy in [ "happ", "tunnel" ]) {
    check(!has_list_update_sources_from_sections(sections, { routing_strategy: strategy }), "Global routing must not start list updates");
    check(!has_nft_list_update_sources_from_sections(sections, { routing_strategy: strategy }), "Global routing must not import subnet lists");
}
check(sprintf("%J", sections) == saved, "Switching strategies must preserve saved lists");
print("Global strategy list source checks passed\n");
