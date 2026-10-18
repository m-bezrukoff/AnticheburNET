const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = process.argv[2] || path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'luci-app-anticheburnet/htdocs/luci-static/resources/view/anticheburnet/happ.js'), 'utf8');
function E(tag, attrs, children) {
  assert.ok(children == null || Array.isArray(children), 'LuCI scalar children are HTML; all text must be passed in arrays');
  return { tag, attrs, children: children || [], isConnected: true,
    dataset: Object.fromEntries(Object.entries(attrs || {}).filter(([key]) => key.startsWith('data-')).map(([key, value]) =>
      [key.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase()), value])),
    open: Object.hasOwn(attrs || {}, 'open'), scrollTop: 0,
    setAttribute(key, value) { this.attrs[key] = value; },
    appendChild(child) { this.children.push(child); },
    replaceChildren(...values) { this.children = values; },
    querySelectorAll(selector) { return descendants(this).filter(node =>
      selector === 'details[data-happ-key]' ? node.tag === 'details' && node.dataset.happKey
        : selector === '[data-focus-key]' ? node.dataset.focusKey
          : selector === '.ac-happ__rule-list' ? node.attrs.class === 'ac-happ__rule-list' : false); },
    querySelector() { return null; },
  };
}
function descendants(node) { return node && typeof node === 'object' ? node.children.flatMap(child => child && typeof child === 'object' ? [child, ...descendants(child)] : []) : []; }
const document = { createElementNS(namespace, tag) { assert.equal(namespace, 'http://www.w3.org/2000/svg'); return E(tag, {}); } };
function text(node) { return node && typeof node === 'object' ? node.children.map(text).join(' ') : String(node ?? ''); }
const callbacks = [];
let requests = 0, removed = false, failing = false, hold = false, resolvePending;
const data = { download_via_proxy: true, download_section: 'main', profiles: [{
  section: 'main', label: 'Main', name: 'Example', source_index: 1, selected: true, enabled: true,
  order: 'block-direct-proxy', domain_strategy: 'IPIfNonMatch', received_rules_known: true,
  rules: { direct: { sites: ['domain:example.ru', '<img onerror=alert(1)>'], ips: ['geoip:ru'] } },
  resources: [{kind:'geoip',url:'https://example.test/geoip.dat',status:'error',error:'proxy_download_failed',
    zones:[{code:'ru',groups:['direct'],configured:true,status:'ready'}]}],
}] };
const app = new Function('baseclass', 'fs', 'poll', 'E', '_', 'document', source)(
  { extend: x => x },
  { exec: async (binary, args) => { assert.equal(binary, '/usr/bin/anticheburnet'); assert.deepEqual(args,['get_happ_status']); requests++; if(hold)await new Promise(resolve=>{resolvePending=resolve});if(failing)throw new Error('read failed');return {code:0,stdout:JSON.stringify(data)}; } },
  { add: (cb, seconds) => { assert.equal(seconds,5); callbacks.push(cb); }, remove: cb => { assert.equal(cb,callbacks[0]); removed=true; } },
  E, x => x, document,
);
const view = app.renderStatus(data);
assert.match(text(view), /geoip:ru/);
assert.ok(descendants(view).some(node => node.tag === 'a' && node.attrs.href === 'https://example.test/geoip.dat'), 'Source links keep the complete original URL');
assert.match(text(view), /Direct fallback is disabled/);
assert.match(text(view), /Yes/);
assert.match(text(view), /<img onerror=alert\(1\)>/, 'Untrusted rule content must remain a text child');
function inspect(node) {
  if (!node || typeof node !== 'object') return;
  assert.ok(!('innerHTML' in node.attrs), 'Status must never render subscription text as HTML');
  node.children.forEach(inspect);
}
inspect(view);
const profile = descendants(view).find(node => node.attrs.class === 'ac-happ__profile');
assert.equal(profile.open, true, 'The selected profile opens initially');
const groups = descendants(view).filter(node => node.attrs.class === 'ac-happ__group');
assert.deepEqual(groups.map(node => node.open), [true, false, false], 'Nonempty rules open while empty actions stay compact');
assert.match(text(view), /Block → Direct → Proxy/, 'The backend rule evaluation order must be preserved');
assert.match(text(view), /Apply changes/, 'Saved configuration must not be presented as applied runtime state');
const unsafeData = structuredClone(data);
unsafeData.profiles[0].resources[0].url = 'javascript:alert(1)';
assert.equal(descendants(app.renderStatus(unsafeData)).filter(node => node.tag === 'a').length, 0, 'Unsafe source protocols must stay plain text');
unsafeData.profiles[0].rules = {};
unsafeData.profiles[0].enabled = false;
unsafeData.profiles[0].received_rules_known = false;
assert.match(text(app.renderStatus(unsafeData)), /HAPP routing is disabled/);
assert.match(text(app.renderStatus(unsafeData)), /Cached normalized rules/);
const resourceData = structuredClone(data);
resourceData.profiles[0].resources = [
  {kind: 'geosite', status: 'not_required', zones: []},
  {kind: 'geoip', status: 'cached', bytes: 16587403, zones: [{code:'ru', groups:['direct'], configured:false, status:'not_prepared'}]},
];
const resourceView = app.renderStatus(resourceData);
assert.deepEqual(descendants(resourceView).filter(node => node.attrs.class === 'ac-happ__resource').map(node => node.attrs['aria-label']), ['GeoIP', 'GeoSite']);
assert.match(text(resourceView), /15.8 MiB/);
assert.match(text(resourceView), /Not prepared/);
assert.match(text(resourceView), /No/);
assert.match(text(app.renderStatus({profiles:[]})),/No HAPP routing profile/);
assert.equal(app.statusLabel('unknown'), 'Unknown');
(async()=>{
  const widget=app.createWidget();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(requests,1);assert.match(text(widget),/geoip:ru/);
  const firstGroups = widget.querySelectorAll('details[data-happ-key]');
  firstGroups[1].open = false;
  firstGroups[2].open = true;
  const ruleList = widget.querySelectorAll('.ac-happ__rule-list')[0];
  ruleList.scrollTop = 80;
  data.profiles[0].resources[0].checked_at = 42;
  await callbacks[0]();
  assert.deepEqual(widget.querySelectorAll('details[data-happ-key]').map(node => node.open), [true, false, true, false], 'Polling must preserve every disclosure');
  assert.equal(widget.querySelectorAll('.ac-happ__rule-list')[0].scrollTop, 80, 'Polling must retain rule-list scroll position');
  hold=true;
  data.profiles[0].resources[0].checked_at = 43;
  const pending = callbacks[0]();
  widget.querySelectorAll('details[data-happ-key]')[2].open = false;
  widget.querySelectorAll('.ac-happ__rule-list')[0].scrollTop = 120;
  hold=false;resolvePending();await pending;
  assert.equal(widget.querySelectorAll('details[data-happ-key]')[2].open, false, 'Changes made during a read must override the initial snapshot');
  assert.equal(widget.querySelectorAll('.ac-happ__rule-list')[0].scrollTop, 120, 'Scrolling during a read must not be undone');
  widget.querySelectorAll('details[data-happ-key]')[0].open = false;
  failing=true;await callbacks[0]();assert.match(text(widget),/Unable to load HAPP/);
  failing=false;await callbacks[0]();assert.match(text(widget),/geoip:ru/,'Unchanged data must render again after a read error');
  assert.equal(widget.querySelectorAll('details[data-happ-key]')[0].open, false, 'Recovery must preserve disclosure state from before the error');
  widget.isConnected=false;await callbacks[0]();
  assert.ok(removed);assert.equal(requests,5,'Detached widgets must stop polling');
  console.log('HAPP rule/resource rendering, safe text and polling checks passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
