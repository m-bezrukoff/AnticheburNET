const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = process.argv[2] || path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'luci-app-anticheburnet/htdocs/luci-static/resources/view/anticheburnet/section.js'), 'utf8');
let savedStrategy;
const context = {
  UCI_PACKAGE: 'anticheburnet',
  uci: { get: () => savedStrategy },
};
vm.runInNewContext(source.slice(source.indexOf('function optionRoutingStrategy('), source.indexOf('function dependsOnRuleConditions(')), context);
const map = { lookupOption: () => null };
let active = true, checks = 0;
const option = { map, checkDepends(sectionId) { assert.equal(this, option); assert.equal(sectionId, 'main'); checks++; return active; } };
context.hideInFullTunnel(option);
assert.equal(option.retain, true, 'Hidden fields must retain their saved UCI values');
for (savedStrategy of [undefined, 'selected', 'happ']) {
  assert.equal(option.checkDepends('main'), true);
  active = false;
  assert.equal(option.checkDepends('main'), false, 'Action dependencies must still apply');
  active = true;
}
savedStrategy = 'tunnel';
const previousChecks = checks;
assert.equal(option.checkDepends('main'), false);
assert.equal(checks, previousChecks, 'Full tunnel hides even fields with matching action dependencies');
let unsavedStrategy = 'selected';
map.parent = { lookupOption(name) {
  assert.equal(name, 'anticheburnet.settings.routing_strategy');
  return [{ formvalue: sid => { assert.equal(sid, 'settings'); return unsavedStrategy; } }, 'settings'];
} };
assert.equal(option.checkDepends('main'), true, 'Unsaved parent selection must override saved tunnel mode');
unsavedStrategy = 'tunnel'; savedStrategy = 'happ';
assert.equal(option.checkDepends('main'), false, 'Cloned modal must honor unsaved tunnel selection');
unsavedStrategy = 'happ';
assert.equal(option.checkDepends('main'), true, 'Switching back must restore the fields');
const names = ['domainConditionOption', 'builtInRulesetOption', 'ruleSetOption', 'dnsRuleSetOption', 'domainIpListsOption', 'dnsDomainListsOption'];
const wiring = source.match(/\[\s*domainConditionOption,[\s\S]*?\]\.forEach\(hideInFullTunnel\);/);
assert.ok(wiring, 'Section condition fields must register strategy visibility');
const registered = [];
vm.runInNewContext(wiring[0], { ...Object.fromEntries(names.map(name => [name, name])), hideInFullTunnel: value => registered.push(value) });
assert.deepEqual(registered, names, 'Every list widget and inline domain field must be hidden in full tunnel');
assert.match(source, /hideInRoutingModes\(builtInRulesetOption, \["happ"\]\)/, 'HAPP must not offer built-in lists');
const builtin = { map, checkDepends: () => true };
context.hideInFullTunnel(builtin);
context.hideInRoutingModes(builtin, ['happ']);
for (unsavedStrategy of ['happ', 'tunnel']) {
  assert.equal(builtin.checkDepends('main'), false, 'Built-in lists must be hidden in both global strategies');
}
unsavedStrategy = 'selected';
assert.equal(builtin.checkDepends('main'), true, 'Selected routing must keep built-in lists available');
assert.equal(builtin.retain, true, 'Hiding HAPP lists must preserve saved list values');
savedStrategy = 'selected'; unsavedStrategy = 'happ';
assert.equal(option.checkDepends('main'), true, 'Manual domain exceptions must stay available in HAPP');
console.log('Routing field visibility, cloned modal selection and saved-value retention passed');
