package rule

import (
	"fmt"
	"sync"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing/common"
)

// PrepareProviderUpdate parses against the live DNS context, then holds the
// local watcher until the provider's entire replacement graph is ready. Managed
// content-addressed files are immutable; later updates use this owner rather
// than watching an obsolete file path.
func (s *LocalRuleSet) PrepareProviderUpdate(path string) (func(), func(), error) {
	s.providerAccess.Lock()
	prepared := &LocalRuleSet{ctx: s.ctx, tag: s.tag, fileFormat: s.fileFormat}
	if err := prepared.reloadFile(path); err != nil {
		s.providerAccess.Unlock()
		return nil, nil, err
	}
	s.access.RLock()
	metadata := s.metadata
	s.access.RUnlock()
	if len(prepared.rules) == 0 || prepared.metadata != metadata {
		s.providerAccess.Unlock()
		return nil, nil, fmt.Errorf("incompatible rule-set predicates")
	}
	var once sync.Once
	abort := func() { once.Do(func() { s.providerAccess.Unlock() }) }
	commit := func() {
		once.Do(func() {
			s.access.Lock()
			watcher := s.watcher
			s.rules, s.metadata = prepared.rules, prepared.metadata
			s.providerPath, s.watcher = path, nil
			callbacks := s.callbacks.Array()
			s.access.Unlock()
			s.providerAccess.Unlock()
			_ = common.Close(common.PtrOrNil(watcher))
			for _, callback := range callbacks {
				callback(s)
			}
		})
	}
	return commit, abort, nil
}

// Matchers can run concurrently with an in-place data update.
func (s *LocalRuleSet) matchProviderRules(metadata *adapter.InboundContext) bool {
	s.access.RLock()
	defer s.access.RUnlock()
	return matchAnyHeadlessRule(s.rules, metadata)
}
