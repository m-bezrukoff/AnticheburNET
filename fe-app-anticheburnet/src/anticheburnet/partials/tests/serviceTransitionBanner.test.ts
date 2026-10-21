import { beforeEach, describe, expect, it } from 'vitest';
import { getServiceTransitionPhase } from '../serviceTransitionBanner.state';
import { store } from '../../services/store.service';
import { applyUiStateToStore } from '../../services/uiState.service';
import {
  clearLocalActionOverlay,
  setLocalServiceAction,
} from '../../services/localActionOverlay.service';
import type { AnticheburNET } from '../../types';

function runtime(
  status: string,
  actions: AnticheburNET.UiState['actions']['service'] = [],
): AnticheburNET.UiState {
  return {
    service: {
      anticheburnet: { running: 1, enabled: 1, status, dns_configured: 1 },
      sing_box: { running: 1, enabled: 0, status: 'running but disabled' },
    },
    capabilities: {
      sing_box_extended: 1,
      sing_box_tiny: 0,
      sing_box_compressed: 0,
      sing_box_tailscale: 1,
      zapret_installed: 0,
      zapret2_installed: 0,
      byedpi_installed: 0,
      server_inbounds_enabled_count: 0,
    },
    actions: { service: actions, subscription: [], latency: [], component: [] },
  };
}

describe('shared service transition banner', () => {
  beforeEach(() => {
    store.reset();
    clearLocalActionOverlay();
  });

  it.each(['starting', 'stopping', 'restarting', 'reloading'] as const)(
    'shows backend %s without the Diagnostics tab being active',
    (phase) => {
      for (const tab of [
        'dashboard',
        'section',
        'server',
        'settings',
        'diagnostic',
        'monitoring',
        'updates',
      ]) {
        store.set({ tabService: { current: tab, all: [] } });
        applyUiStateToStore(runtime(phase));
        expect(getServiceTransitionPhase(store.get())).toBe(phase);
      }
    },
  );

  it('keeps a local restart visible while the old running status is still returned', () => {
    setLocalServiceAction('restart', true);
    applyUiStateToStore(runtime('running & enabled'));
    expect(getServiceTransitionPhase(store.get())).toBe('restarting');
    applyUiStateToStore(runtime('starting'));
    expect(getServiceTransitionPhase(store.get())).toBe('restarting');
    setLocalServiceAction('restart', false);
    applyUiStateToStore(runtime('running & enabled'));
    expect(getServiceTransitionPhase(store.get())).toBeNull();
  });

  it.each(['running & enabled', 'stopped & disabled', 'failed', ''])(
    'does not invent progress for %s',
    (status) => {
      applyUiStateToStore(runtime(status));
      expect(getServiceTransitionPhase(store.get())).toBeNull();
    },
  );

  it('shows a running remote action before the service status changes and clears at completion', () => {
    applyUiStateToStore(
      runtime('running & enabled', [
        { kind: 'service', action: 'restart', running: true, success: true },
      ] as AnticheburNET.UiState['actions']['service']),
    );
    expect(getServiceTransitionPhase(store.get())).toBe('restarting');
    applyUiStateToStore(runtime('running & enabled'));
    expect(getServiceTransitionPhase(store.get())).toBeNull();
  });

  it('shows the restart stage of a component update but not its download stage', () => {
    const current = store.get().updatesActions;
    store.set({
      updatesActions: {
        ...current,
        singBoxInstall: { loading: true, progress: { stage: 'downloading' } },
      },
    });
    expect(getServiceTransitionPhase(store.get())).toBeNull();
    store.set({
      updatesActions: {
        ...current,
        singBoxInstall: { loading: true, progress: { stage: 'restarting' } },
      },
    });
    expect(getServiceTransitionPhase(store.get())).toBe('restarting');
    store.set({ updatesActions: current });
    expect(getServiceTransitionPhase(store.get())).toBeNull();
  });
});
