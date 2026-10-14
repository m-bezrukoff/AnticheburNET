package provider

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/provider"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/service"
)

// This provider is updated explicitly, never by a file watcher. PUT returns only
// after the complete validated outbound graph has been installed in memory.
type AnticheburNETProvider struct {
	provider.Adapter
	ctx        context.Context
	router     adapter.Router
	logFactory log.Factory
	manager    adapter.OutboundManager
	path       string
	access     sync.RWMutex
	tags       []string
	updated    time.Time
	revision   string
}

func RegisterProviderAnticheburNET(registry *provider.Registry) {
	provider.Register[option.ProviderLocalOptions](registry, "anticheburnet", NewProviderAnticheburNET)
}

func NewProviderAnticheburNET(ctx context.Context, router adapter.Router, logFactory log.Factory, tag string, options option.ProviderLocalOptions) (adapter.Provider, error) {
	p := &AnticheburNETProvider{
		Adapter: provider.NewAdapter(ctx, router, service.FromContext[adapter.OutboundManager](ctx), logFactory, logFactory.NewLogger("provider/anticheburnet["+tag+"]"), tag, "anticheburnet", option.ProviderHealthCheckOptions{}),
		ctx:     ctx, router: router, logFactory: logFactory,
		manager: service.FromContext[adapter.OutboundManager](ctx), path: options.Path,
	}
	if err := p.Update(); err != nil {
		return nil, err
	}
	return p, nil
}

func (p *AnticheburNETProvider) Start() error { return p.Adapter.Start() }
func (p *AnticheburNETProvider) Close() error { return nil }
func (p *AnticheburNETProvider) UpdatedAt() time.Time {
	p.access.RLock()
	defer p.access.RUnlock()
	return p.updated
}
func (p *AnticheburNETProvider) Revision() string {
	p.access.RLock()
	defer p.access.RUnlock()
	return p.revision
}
func (p *AnticheburNETProvider) Outbounds() []adapter.Outbound {
	p.access.RLock()
	defer p.access.RUnlock()
	result := make([]adapter.Outbound, 0, len(p.tags))
	for _, tag := range p.tags {
		if ob, ok := p.manager.Outbound(tag); ok {
			result = append(result, ob)
		}
	}
	return result
}
func (p *AnticheburNETProvider) Outbound(tag string) (adapter.Outbound, bool) {
	p.access.RLock()
	defer p.access.RUnlock()
	for _, owned := range p.tags {
		if owned == tag {
			return p.manager.Outbound(tag)
		}
	}
	return nil, false
}

func (p *AnticheburNETProvider) Update() error {
	p.access.Lock()
	defer p.access.Unlock()
	content, err := os.ReadFile(p.path)
	if err != nil {
		return err
	}
	revision := fmt.Sprintf("%x", sha256.Sum256(content))
	if revision == p.revision {
		return nil
	}
	var payload struct {
		Outbounds []option.Outbound `json:"outbounds"`
	}
	if err = json.UnmarshalContext(p.ctx, content, &payload); err != nil {
		return err
	}
	if len(payload.Outbounds) == 0 {
		return fmt.Errorf("refusing empty AnticheburNET provider")
	}
	manager, ok := p.manager.(interface {
		ReplaceProvider(context.Context, adapter.Router, log.Factory, string, []string, []option.Outbound) error
	})
	if !ok {
		return fmt.Errorf("outbound manager does not support atomic provider updates")
	}
	if err = manager.ReplaceProvider(p.ctx, p.router, p.logFactory, p.Tag(), p.tags, payload.Outbounds); err != nil {
		return err
	}
	p.tags = p.tags[:0]
	for _, ob := range payload.Outbounds {
		p.tags = append(p.tags, ob.Tag)
	}
	p.updated = time.Now()
	p.revision = revision
	return nil
}
