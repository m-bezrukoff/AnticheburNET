// Windows audit helper. Linux CI uses its native ucode interpreter directly.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const wasm = process.env.ANTICHEBURNET_UCODE_WASM;
if (!wasm) throw new Error('ANTICHEBURNET_UCODE_WASM must name the local ucode.js runtime');
(async () => {
  const M = await require(path.resolve(wasm))();
  const pointer = value => { const size = M.lengthBytesUTF8(value), p = M._malloc(size + 1); M.stringToUTF8(value, p, size + 1); return p; };
  const write = (name, value) => { const p = pointer(name), q = pointer(value); M._ucode_vfs_write(p, q, -1); M._free(p); M._free(q); };
  for (const name of ['core/xray.uc', 'core/common.uc', 'singbox/constants.uc']) write('/usr/lib/' + name, fs.readFileSync(path.join(root, 'anticheburnet/files/usr/lib', name), 'utf8'));
  const value = fs.readFileSync(0, 'utf8');
  const port = Number(process.argv[2]);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid native test port');
  write('/prepare.uc', 'push(REQUIRE_SEARCH_PATH,"/usr/lib/*.uc"); let x=require("core.xray"); print(sprintf("%J",x.prepare(json(' + JSON.stringify(value) + '),' + port + ')));');
  const p = pointer('/prepare.uc'); M._ucode_fs_run(p); M._free(p);
  const error = M.UTF8ToString(M._ucode_get_error());
  if (error) throw new Error(error);
  process.stdout.write(M.UTF8ToString(M._ucode_get_output()));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
