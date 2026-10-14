"""Install the managed dynamic provider into the pinned sing-box checkout."""
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1])
root = Path(__file__).resolve().parent
shutil.copyfile(root / "sing-box/provider_anticheburnet.go", source / "provider/local/anticheburnet.go")
shutil.copyfile(root / "sing-box/outbound_provider.go", source / "adapter/outbound/provider.go")

def edit(relative, before, after, marker=None):
    path = source / relative
    text = path.read_text(encoding="utf-8")
    if (marker or after) in text:
        return
    if before not in text:
        raise SystemExit(f"Pinned provider patch context missing: {relative}")
    path.write_text(text.replace(before, after, 1), encoding="utf-8", newline="\n")

edit("provider/local/provider.go", "func RegisterProviderLocal(registry *provider.Registry) {", "func RegisterProviderLocal(registry *provider.Registry) {\n\tRegisterProviderAnticheburNET(registry)", "RegisterProviderAnticheburNET(registry)")
edit("adapter/outbound/manager.go", '"github.com/sagernet/sing-box/log"', '"github.com/sagernet/sing-box/log"\n\t"github.com/sagernet/sing-box/option"')
edit("adapter/outbound/manager.go", "type Manager struct {", "type Manager struct {\n\tproviderOptions map[string]map[string]option.Outbound", "providerOptions")
edit("adapter/outbound/manager.go", "type Manager struct {", "type Manager struct {\n\tproviderDelegate *Manager", "providerDelegate")
for name, returns in (("Outbounds", "[]adapter.Outbound"), ("Default", "adapter.Outbound")):
    before = f"func (m *Manager) {name}() {returns} {{\n\tm.access.RLock()\n\tdefer m.access.RUnlock()"
    edit("adapter/outbound/manager.go", before, before + f"\n\tif m.providerDelegate != nil {{ return m.providerDelegate.{name}() }}", f"return m.providerDelegate.{name}()")
before = "func (m *Manager) Outbound(tag string) (adapter.Outbound, bool) {\n\tm.access.RLock()"
edit("adapter/outbound/manager.go", before, before + "\n\tif delegate := m.providerDelegate; delegate != nil { m.access.RUnlock(); return delegate.Outbound(tag) }", "return delegate.Outbound(tag)")
# DNS and other long-lived consumers must resolve the current outbound, rather
# than cache the object that existed before a provider update.
edit("common/dialer/detour.go", "\td.initOnce.Do(d.init)\n\treturn d.dialer, d.initErr", """\tif d.detour != "" {
        dialer, loaded := d.outboundManager.Outbound(d.detour)
        if !loaded { return nil, E.New("outbound detour not found: ", d.detour) }
        return dialer, nil
    }
    dialer := d.outboundManager.Default()
    if dialer == nil { return nil, E.New("default outbound not found") }
    return dialer, nil""", "default outbound not found")
# Include a revision in GET /providers/proxies/{name} for runtime verification.
edit("experimental/clashapi/provider.go", 'info.Put("updatedAt", p.UpdatedAt())', 'info.Put("updatedAt", p.UpdatedAt())\n\tif p, ok := p.(interface{ Revision() string }); ok { info.Put("revision", p.Revision()) }', 'Revision() string')
edit("experimental/clashapi/provider.go", "render.JSON(w, r, providerInfo(server, provider))", """if value, ok := provider.(interface{ Revision() string }); ok && r.URL.Query().Get("revision") == "true" {
            render.JSON(w, r, render.M{"name": provider.Tag(), "revision": value.Revision()})
            return
        }
        render.JSON(w, r, providerInfo(server, provider))""", 'r.URL.Query().Get("revision")')

for network in ("TCP", "UDP"):
    edit("route/route.go", f"if !common.Contains(r.defaultOutbound.Network(), N.Network{network})", f"defaultOutbound := r.outbound.Default()\n\t\tif defaultOutbound == nil {{ return E.New(\"default outbound not found\") }}\n\t\tif !common.Contains(defaultOutbound.Network(), N.Network{network})", f"if !common.Contains(defaultOutbound.Network(), N.Network{network})")
path = source / "route/route.go"
text = path.read_text(encoding="utf-8").replace("r.defaultOutbound.Tag()", "defaultOutbound.Tag()").replace("selectedOutbound = r.defaultOutbound", "selectedOutbound = defaultOutbound")
path.write_text(text, encoding="utf-8", newline="\n")
