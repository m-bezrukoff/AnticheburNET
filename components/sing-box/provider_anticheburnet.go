package provider

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"reflect"
	"regexp"
	"strings"
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
	ctx           context.Context
	router        adapter.Router
	logFactory    log.Factory
	manager       adapter.OutboundManager
	path          string
	access        sync.RWMutex
	tags          []string
	updated       time.Time
	revision      string
	configuration map[string]any
}

func (p *AnticheburNETProvider) Capabilities() []string {
	return []string{"happ-ruleset-update-v1"}
}

var happRuleSetPath = regexp.MustCompile(`/[a-f0-9]{64}\.json$`)

// Only the content-addressed file of an existing Happ GeoIP/GeoSite set may
// change. Tags, sources, formats, DNS policy and all other settings stay equal.
func providerConfiguration(value map[string]any) map[string]any {
	result := make(map[string]any, len(value))
	for key, item := range value {
		result[key] = item
	}
	route, ok := value["route"].(map[string]any)
	if !ok {
		return result
	}
	copyRoute := make(map[string]any, len(route))
	for key, item := range route {
		copyRoute[key] = item
	}
	result["route"] = copyRoute
	rules, ok := route["rule_set"].([]any)
	if !ok {
		return result
	}
	copyRules := append([]any(nil), rules...)
	copyRoute["rule_set"] = copyRules
	for i, item := range rules {
		rule, ok := item.(map[string]any)
		if !ok {
			continue
		}
		tag, _ := rule["tag"].(string)
		path, _ := rule["path"].(string)
		if rule["type"] != "local" || rule["format"] != "source" ||
			(!strings.Contains(tag, "-happ-geoip-") && !strings.Contains(tag, "-happ-geosite-")) || !happRuleSetPath.MatchString(path) {
			continue
		}
		copyRule := make(map[string]any, len(rule))
		for key, value := range rule {
			copyRule[key] = value
		}
		copyRule["path"] = happRuleSetPath.ReplaceAllString(path, "/<happ-content>.json")
		copyRules[i] = copyRule
	}
	return result
}

func (p *AnticheburNETProvider) prepareRuleSets(configuration map[string]any) (func(), func(), error) {
	if p.revision == "" || reflect.DeepEqual(p.configuration, configuration) {
		return func() {}, func() {}, nil
	}
	if !reflect.DeepEqual(providerConfiguration(p.configuration), providerConfiguration(configuration)) {
		return nil, nil, fmt.Errorf("subscription configuration is incompatible with the running service")
	}
	var commits, aborts []func()
	abort := func() {
		for i := len(aborts) - 1; i >= 0; i-- {
			aborts[i]()
		}
	}
	oldRoute, _ := p.configuration["route"].(map[string]any)
	newRoute, _ := configuration["route"].(map[string]any)
	oldRules, _ := oldRoute["rule_set"].([]any)
	newRules, _ := newRoute["rule_set"].([]any)
	for i, item := range newRules {
		oldRule, oldOK := oldRules[i].(map[string]any)
		newRule, newOK := item.(map[string]any)
		if !oldOK || !newOK || reflect.DeepEqual(oldRule["path"], newRule["path"]) {
			continue
		}
		tag, _ := newRule["tag"].(string)
		path, _ := newRule["path"].(string)
		ruleSet, found := p.router.RuleSet(tag)
		updater, supported := ruleSet.(interface {
			PrepareProviderUpdate(string) (func(), func(), error)
		})
		if !found || !supported {
			abort()
			return nil, nil, fmt.Errorf("rule-set %s does not support provider updates", tag)
		}
		commit, cancel, err := updater.PrepareProviderUpdate(path)
		if err != nil {
			abort()
			return nil, nil, fmt.Errorf("prepare rule-set %s: %w", tag, err)
		}
		commits, aborts = append(commits, commit), append(aborts, cancel)
	}
	return func() {
		for _, commit := range commits {
			commit()
		}
	}, abort, nil
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

func (p *AnticheburNETProvider) Start(stage adapter.StartStage, scope *adapter.Scope) error {
	if stage != adapter.StartStateStart {
		return nil
	}
	scope.Add(p.Close)
	return p.Adapter.Start()
}
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
		Outbounds     []option.Outbound `json:"outbounds"`
		Configuration map[string]any    `json:"configuration"`
	}
	if err = json.UnmarshalContext(p.ctx, content, &payload); err != nil {
		return err
	}
	if len(payload.Outbounds) == 0 {
		return fmt.Errorf("refusing empty AnticheburNET provider")
	}
	manager, ok := p.manager.(interface {
		ReplaceProvider(context.Context, adapter.Router, log.Factory, string, []string, []option.Outbound, func()) error
	})
	if !ok {
		return fmt.Errorf("outbound manager does not support atomic provider updates")
	}
	commitRules, abortRules, err := p.prepareRuleSets(payload.Configuration)
	if err != nil {
		return err
	}
	defer abortRules()
	if err = manager.ReplaceProvider(p.ctx, p.router, p.logFactory, p.Tag(), p.tags, payload.Outbounds, commitRules); err != nil {
		return err
	}
	p.tags = p.tags[:0]
	for _, ob := range payload.Outbounds {
		p.tags = append(p.tags, ob.Tag)
	}
	p.updated = time.Now()
	p.revision = revision
	p.configuration = payload.Configuration
	return nil
}
