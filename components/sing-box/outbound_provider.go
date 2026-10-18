package outbound

import (
	"context"
	"fmt"
	"reflect"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/urltest"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common"
	"github.com/sagernet/sing/service"
)

// Build and start the replacement graph in isolation. The live lookup table is
// swapped only after every dependency and every new outbound is ready.
func (m *Manager) ReplaceProvider(ctx context.Context, router adapter.Router, factory log.Factory, owner string, previousTags []string, options []option.Outbound) error {
	m.access.RLock()
	started, stage := m.started, m.stage
	old := make(map[string]adapter.Outbound, len(m.outboundByTag))
	for tag, ob := range m.outboundByTag {
		old[tag] = ob
	}
	oldOptions := m.providerOptions[owner]
	m.access.RUnlock()
	pool := NewManager(m.logger, m.registry, m.endpoint, m.defaultTag)
	pool.Initialize(m.defaultOutboundFallback)
	previous := make(map[string]bool)
	for _, tag := range previousTags {
		previous[tag] = true
	}
	for tag, ob := range old {
		if !previous[tag] {
			pool.outboundByTag[tag] = ob
		}
	}
	newOptions := make(map[string]option.Outbound)
	created := make(map[string]adapter.Outbound)
	changed := make(map[string]bool)
	committed := false
	defer func() {
		if !committed {
			for _, ob := range created {
				_ = common.Close(ob)
			}
		}
	}()
	newCtx := service.ContextWith[adapter.OutboundManager](service.ExtendContext(ctx), pool)
	for _, opt := range options {
		if opt.Tag == "" || newOptions[opt.Tag].Tag != "" {
			return fmt.Errorf("empty or duplicate provider outbound: %s", opt.Tag)
		}
		if _, exists := pool.outboundByTag[opt.Tag]; exists {
			return fmt.Errorf("provider outbound collides with an external outbound: %s", opt.Tag)
		}
		newOptions[opt.Tag] = opt
		changed[opt.Tag] = old[opt.Tag] == nil || !reflect.DeepEqual(opt, oldOptions[opt.Tag])
		if !changed[opt.Tag] {
			pool.outboundByTag[opt.Tag] = old[opt.Tag]
			continue
		}
		ob, err := m.registry.CreateOutbound(newCtx, router, factory.NewLogger("outbound/"+opt.Type+"["+opt.Tag+"]"), opt.Tag, opt.Type, opt.Options)
		if err != nil {
			return fmt.Errorf("create %s: %w", opt.Tag, err)
		}
		created[opt.Tag] = ob
		pool.outboundByTag[opt.Tag] = ob
	}
	// A group or dialer caches its dependencies. Rebuild every dependent of a
	// changed node even when its own JSON is unchanged (for example a new password).
	for again := true; again; {
		again = false
		for tag, opt := range newOptions {
			if changed[tag] {
				continue
			}
			for _, dependency := range pool.outboundByTag[tag].Dependencies() {
				if changed[dependency] {
					ob, err := m.registry.CreateOutbound(newCtx, router, factory.NewLogger("outbound/"+opt.Type+"["+tag+"]"), tag, opt.Type, opt.Options)
					if err != nil {
						return fmt.Errorf("create dependent %s: %w", tag, err)
					}
					created[tag], pool.outboundByTag[tag] = ob, ob
					changed[tag] = true
					again = true
					break
				}
			}
		}
	}
	// Topological order also validates missing references and cycles before start.
	ordered := make([]adapter.Outbound, 0, len(pool.outboundByTag))
	ready := make(map[string]bool)
	for len(ready) < len(pool.outboundByTag) {
		progress := false
		for tag, ob := range pool.outboundByTag {
			if ready[tag] {
				continue
			}
			canStart := true
			for _, dependency := range ob.Dependencies() {
				if _, exists := pool.outboundByTag[dependency]; !exists {
					return fmt.Errorf("outbound %s: missing dependency %s", tag, dependency)
				}
				if !ready[dependency] {
					canStart = false
				}
			}
			if canStart {
				ordered = append(ordered, ob)
				ready[tag] = true
				progress = true
			}
		}
		if !progress {
			return fmt.Errorf("provider outbound dependency cycle")
		}
	}
	pool.outbounds = ordered
	pool.defaultOutbound = pool.outboundByTag[m.defaultTag]
	if m.defaultTag != "" && pool.defaultOutbound == nil {
		return fmt.Errorf("provider cannot remove the default outbound: %s", m.defaultTag)
	}
	if pool.defaultOutbound == nil {
		pool.defaultOutbound = m.defaultOutbound
	}
	if started {
		for _, startStage := range adapter.ListStartStages {
			if startStage > stage {
				break
			}
			for _, ob := range ordered {
				if created[ob.Tag()] != nil {
					if err := adapter.LegacyStart(ob, startStage); err != nil {
						return fmt.Errorf("start %s: %w", ob.Tag(), err)
					}
				}
			}
		}
	}
	// Membership changes rebuild selectors. Transfer the live user choice before
	// publishing the graph, even when the disk cache is disabled or unavailable.
	// This also avoids a brief detour through the new selector's default profile.
	for tag, ob := range created {
		selector, ok := ob.(interface {
			adapter.OutboundGroup
			SelectOutbound(string) bool
		})
		if !ok || ob.Type() != "selector" {
			continue
		}
		previous, ok := old[tag].(adapter.OutboundGroup)
		if !ok {
			continue
		}
		selected := previous.Now()
		if common.Contains(selector.All(), selected) && !selector.SelectOutbound(selected) {
			return fmt.Errorf("restore provider selector %s: %s", tag, selected)
		}
	}
	dependencies := make(map[string][]string)
	for _, ob := range ordered {
		for _, dependency := range ob.Dependencies() {
			dependencies[dependency] = append(dependencies[dependency], ob.Tag())
		}
	}
	m.access.Lock()
	m.outboundByTag, m.outbounds, m.dependByTag = pool.outboundByTag, ordered, dependencies
	m.defaultOutbound = pool.defaultOutbound
	if m.providerOptions == nil {
		m.providerOptions = make(map[string]map[string]option.Outbound)
	}
	m.providerOptions[owner] = newOptions
	m.access.Unlock()
	// Constructor contexts retain this temporary manager. Delegate future lookups
	// to the live manager, then release the snapshot maps so unchanged nodes do
	// not retain every previous provider generation indefinitely.
	pool.access.Lock()
	pool.providerDelegate = m
	pool.outboundByTag, pool.outbounds, pool.defaultOutbound = nil, nil, nil
	pool.access.Unlock()
	committed = true
	// Readers holding the old group can finish; no service, inbound, DNS or API
	// is stopped. Unchanged objects (and their connection/history state) are reused.
	for tag, ob := range old {
		if previous[tag] && (changed[tag] || newOptions[tag].Tag == "") {
			if history := service.PtrFromContext[urltest.HistoryStorage](ctx); history != nil {
				history.DeleteURLTestHistory(tag)
			}
			_ = common.Close(ob)
		}
	}
	return nil
}
