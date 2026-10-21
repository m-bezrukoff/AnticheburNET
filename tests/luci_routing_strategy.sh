#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node - "$root" <<'JS'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert/strict');
const source = fs.readFileSync(process.argv[2] + '/luci-app-anticheburnet/htdocs/luci-static/resources/view/anticheburnet/anticheburnet.js', 'utf8');
const code = source.slice(source.indexOf('function addRoutingStrategy('), source.indexOf('const EntryPoint ='));
const registered = [], options = {};
function ListValue() {}
ListValue.prototype.load = function () { return 'saved-target'; };
const context = {
  form: { NamedSection() {}, ListValue }, UCI_PACKAGE: 'anticheburnet', _: s => s,
  document: { createDocumentFragment: () => ({ fragment: true }) },
  uci: { sections: (_config, _type, callback) => [
    { '.name': 'main', action: 'connection', enabled: '1', label: 'Main' },
    { '.name': 'off', action: 'connection', enabled: '0' },
    { '.name': 'bypass', action: 'bypass', enabled: '1' },
    { '.name': 'legacy', action: 'proxy' },
  ].forEach(callback) },
};
const happNode = {};
const strategyNode = { querySelector: selector => selector === '.ac-happ-field'
  ? happNode : ({ removeAttribute: key => assert.equal(key, 'id') }) };
const section = {
  render: async () => strategyNode,
  option: (_type, key, _title, description) => options[key] = {
    description,
    keylist: [], vallist: [], dependencies: [],
    value(k, v) { this.keylist.push(k); this.vallist.push(v); },
    depends(k, v) { this.dependencies.push([k, v]); },
  },
};
const map = { section: (...args) => { registered.push(args); return section; } };
let inserted = 0;
const rules = { render: async () => {
  const children = ['table', 'add-section'];
  return {
    get firstChild() { return children[0]; },
    appendChild(node) { assert.equal(node, happNode); children.push(node); },
    insertBefore(node, before) {
      assert.equal(node, strategyNode); assert.equal(before, 'table');
      children.splice(children.indexOf(before), 0, node);
      assert.deepEqual(children, [strategyNode, 'table', 'add-section', happNode]);
      inserted++;
    },
  };
} };
vm.runInNewContext(code, context);
context.addRoutingStrategy(map, rules);
assert.equal(registered.length, 1);
assert.equal(registered[0][1], 'settings');
assert.deepEqual(options.routing_strategy.keylist, ['happ', 'selected', 'tunnel']);
assert.equal(options.routing_strategy.default, 'tunnel');
assert.equal(options.routing_strategy.rmempty, false);
assert.equal(options.routing_strategy.description, 'Torrent traffic always goes directly.');
assert.equal(options.routing_strategy.dependencies.length, 0, 'Torrent notice must remain visible for every strategy');
assert.deepEqual(options._happ_status.dependencies.map(row => Array.from(row)), [['routing_strategy','happ']]);
assert.equal(typeof options._happ_status.renderWidget, 'function');
assert.equal(options.routing_section.load('settings'), 'saved-target');
assert.deepEqual(Array.from(options.routing_section.keylist), ['', 'main', 'legacy']);
(async () => {
  assert.equal((await section.render()).fragment, true);
  await rules.render(); await rules.render();
  assert.equal(inserted, 2, 'Strategy must remain in Sections after a form refresh');
  console.log('Routing strategy choices, connection filtering and Sections placement passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
JS
node "$root/tests/luci_routing_conditions.cjs" "$root"
