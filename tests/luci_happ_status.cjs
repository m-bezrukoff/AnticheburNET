const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = process.argv[2] || path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'luci-app-anticheburnet/htdocs/luci-static/resources/view/anticheburnet/happ.js'), 'utf8');
function E(tag, attrs, children) {
  return { tag, attrs, children: Array.isArray(children) ? children : [children], isConnected: true,
    replaceChildren(...values) { this.children = values; } };
}
function text(node) { return node && typeof node === 'object' ? node.children.map(text).join(' ') : String(node ?? ''); }
const callbacks = [];
let requests = 0, removed = false, failing = false;
const data = { download_via_proxy: true, download_section: 'main', profiles: [{
  section: 'main', label: 'Main', name: 'Example', source_index: 1, selected: true, enabled: true,
  order: 'block-direct-proxy', domain_strategy: 'IPIfNonMatch', received_rules_known: true,
  rules: { direct: { sites: ['domain:example.ru', '<img onerror=alert(1)>'], ips: ['geoip:ru'] } },
  resources: [{kind:'geoip',url:'https://example.test/geoip.dat',status:'error',error:'proxy_download_failed',
    zones:[{code:'ru',groups:['direct'],configured:true,status:'ready'}]}],
}] };
const app = new Function('baseclass', 'fs', 'poll', 'E', '_', source)(
  { extend: x => x },
  { exec: async (binary, args) => { assert.equal(binary, '/usr/bin/anticheburnet'); assert.deepEqual(args,['get_happ_status']); requests++; if(failing)throw new Error('read failed');return {code:0,stdout:JSON.stringify(data)}; } },
  { add: (cb, seconds) => { assert.equal(seconds,5); callbacks.push(cb); }, remove: cb => { assert.equal(cb,callbacks[0]); removed=true; } },
  E, x => x,
);
const view = app.renderStatus(data);
assert.match(text(view), /geoip:ru/);
assert.match(text(view), /https:\/\/example.test\/geoip.dat/);
assert.match(text(view), /Direct fallback is disabled/);
assert.match(text(view), /Yes/);
assert.match(text(view), /<img onerror=alert\(1\)>/, 'Untrusted rule content must remain a text child');
function inspect(node) {
  if (!node || typeof node !== 'object') return;
  assert.ok(!('innerHTML' in node.attrs), 'Status must never render subscription text as HTML');
  node.children.forEach(inspect);
}
inspect(view);
assert.match(text(app.renderStatus({profiles:[]})),/No HAPP routing profile/);
assert.equal(app.statusLabel('unknown'), 'Unknown');
(async()=>{
  const widget=app.createWidget();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(requests,1);assert.match(text(widget),/geoip:ru/);
  failing=true;await callbacks[0]();assert.match(text(widget),/Unable to load HAPP/);
  failing=false;await callbacks[0]();assert.match(text(widget),/geoip:ru/,'Unchanged data must render again after a read error');
  widget.isConnected=false;await callbacks[0]();
  assert.ok(removed);assert.equal(requests,3,'Detached widgets must stop polling');
  console.log('HAPP rule/resource rendering, safe text and polling checks passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
