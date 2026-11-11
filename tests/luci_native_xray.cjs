const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'luci-app-anticheburnet/htdocs/luci-static/resources/view/anticheburnet/section.js'), 'utf8');
const start = source.indexOf('function showOutboundJsonSettingsModal(');
const end = source.indexOf('function validateOutboundJsonItemsBeforeSave', start);
let validated, saved;
class JSONMap {
  constructor(data) { this.data = data; this.options = {}; }
  section() { return { option: (_type, key) => {
    const option = { formvalue: () => this.data.settings[key], depends() {}, value() {} };
    this.options[key] = option;
    return option;
  } }; }
}
const context = {
  _: text => text,
  form: { JSONMap },
  main: { validateOutboundJson(value, tags) { validated = JSON.parse(value); return { valid: !!validated.type && !!validated.tag && !tags.includes(validated.tag), message: 'invalid' }; } },
  configureTextareaOption() {},
  renderStackedJsonSettingsModal: (_title, map, save) => ({ map, save }),
  addDynamicListItem(_widget, value) { saved = value; },
  setDynamicListItemValue(_node, value) { saved = value; },
  updateDynamicListItemLabel() {},
  outboundJsonDisplayTag(value) { return JSON.parse(value).tag; },
};
vm.runInNewContext(source.slice(start, end), context);
const native = { type: 'xray', tag: 'Drive', config: { outbounds: [{ protocol: 'vless', streamSettings: { network: 'xdrive', xdriveSettings: { service: 'google-drive', secrets: ['id','secret','token'], remoteFolder: 'folder' } }, mux: { enabled: true, concurrency: 128 } }] } };
let modal = context.showOutboundJsonSettingsModal('section', JSON.stringify(native), null, null, null, { adding: true });
assert.equal(modal.map.data.settings.engine, 'xray');
assert.deepEqual(JSON.parse(modal.map.data.settings.outbound_json), native.config);
assert.equal(modal.map.options.outbound_json.validate('settings', modal.map.data.settings.outbound_json), true);
assert.deepEqual(validated, native);
modal.map.data.settings.native_tag = 'Renamed';
modal.save(modal.map.data.settings);
assert.deepEqual(JSON.parse(saved), { ...native, tag: 'Renamed' });
const ordinary = { type: 'socks', tag: 'proxy', server: 'example.com', server_port: 1080 };
modal = context.showOutboundJsonSettingsModal('section', JSON.stringify(ordinary), null, null, {}, {});
assert.equal(modal.map.data.settings.engine, 'sing-box');
assert.equal(modal.map.options.outbound_json.validate('settings', modal.map.data.settings.outbound_json), true);
modal.save(modal.map.data.settings);
assert.deepEqual(JSON.parse(saved), ordinary);
console.log('Native Xray editor preserves full config and existing sing-box entries');
