import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AnticheburNET } from '../../../types';

const mocks = vi.hoisted(() => ({
  getDashboardSections: vi.fn(),
  subscriptionUpdateStart: vi.fn(),
  waitSubscriptionUpdateJob: vi.fn(),
  latencyTestStart: vi.fn(),
  waitLatencyTestJob: vi.fn(),
  renderSections: vi.fn(
    (options: {
      section: AnticheburNET.OutboundGroup;
      onUpdateSubscription: (section: AnticheburNET.OutboundGroup) => void;
    }) => options,
  ),
  renderWidget: vi.fn(),
  refreshRuntimeUiState: vi.fn(),
  fetchServicesInfo: vi.fn(),
}));
vi.mock('../../../../helpers', () => ({
  getClashWsUrl: () => '',
  isCopyableProxyLink: () => true,
  onMount: () => Promise.resolve(),
  preserveScrollForPage: (run: () => unknown) => run(),
}));
vi.mock('../../../../helpers/copyToClipboard', () => ({
  copyToClipboard: vi.fn(),
}));
vi.mock('../../../../helpers/showToast', () => ({ showToast: vi.fn() }));
vi.mock('../../../methods', () => ({
  CustomAnticheburNETMethods: {
    getDashboardSections: mocks.getDashboardSections,
  },
  AnticheburNETShellMethods: { ...mocks, uiActionAck: vi.fn() },
}));
vi.mock('../../../methods/custom/getClashApiSecret', () => ({
  getClashApiSecret: async () => '',
}));
vi.mock('../../../fetchers/fetchServicesInfo', () => ({
  fetchServicesInfo: mocks.fetchServicesInfo,
}));
vi.mock('../partials', () => ({
  renderSections: mocks.renderSections,
  renderWidget: mocks.renderWidget,
  renderFlagEmojis: vi.fn(),
  getLatencyTestLabel: () => '',
}));
vi.mock('../../../services', async () => ({
  store: (await import('../../../services/store.service')).store,
  logger: { debug: vi.fn(), error: vi.fn() },
  socket: { subscribe: vi.fn(), resetAll: vi.fn() },
  markUiActionOwned: vi.fn(),
  setLocalLatencyAction: vi.fn(),
  setLocalSubscriptionAction: vi.fn(),
  shouldNotifyOwnedUiAction: () => true,
}));
vi.mock('../../../services/runtimeUiState.service', () => ({
  getCachedRuntimeUiState: () => ({}),
  refreshRuntimeUiState: mocks.refreshRuntimeUiState,
  subscribeRuntimeUiState: () => () => {},
}));

function section(name: string, latency: number): AnticheburNET.OutboundGroup {
  return {
    code: name,
    sectionName: name,
    displayName: name,
    withTagSelect: true,
    outbounds: [
      {
        code: `${name}-node`,
        displayName: name,
        latency,
        type: 'vless',
        link: `vless://${name}`,
        selected: true,
      },
    ],
  };
}
async function settle() {
  for (let i = 0; i < 40; i++) await Promise.resolve();
}

describe('dashboard subscription refresh', () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('keeps service checkmarks and tiles during a provider update, probes groups, then replaces cached values', async () => {
    const { store } = await import('../../../services/store.service');
    const toggle = vi.fn();
    vi.stubGlobal('document', {
      getElementById: (id: string) =>
        id === 'dashboard-status'
          ? { classList: { toggle } }
          : id === 'dashboard-sections-grid'
            ? { replaceChildren: vi.fn(), querySelectorAll: () => [] }
            : null,
    });
    store.set({
      tabService: { current: 'dashboard', all: [] },
      servicesInfoWidget: {
        loading: false,
        failed: false,
        data: {
          singbox: 1,
          anticheburnetRunning: 1,
          anticheburnetEnabled: 1,
          anticheburnetStatus: '',
        },
      },
    });
    let data = [section('main', 42), section('other', 67)];
    mocks.getDashboardSections.mockImplementation(async () => ({
      success: true,
      data,
    }));
    mocks.subscriptionUpdateStart.mockResolvedValue({
      success: true,
      data: { job_id: 'sub-1' },
    });
    let finishSubscription!: (result: unknown) => void;
    mocks.waitSubscriptionUpdateJob.mockImplementation(
      () =>
        new Promise((resolve) => {
          finishSubscription = resolve;
        }),
    );
    const finishLatency: Array<() => void> = [];
    mocks.latencyTestStart.mockImplementation(async (_type, name) => ({
      success: true,
      data: { job_id: `test-${name}` },
    }));
    mocks.waitLatencyTestJob.mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          finishLatency.push(resolve);
        }),
    );
    mocks.fetchServicesInfo.mockImplementation(async () => {
      store.set({
        servicesInfoWidget: {
          ...store.get().servicesInfoWidget,
          data: {
            ...store.get().servicesInfoWidget.data,
            anticheburnetRunning: 1,
          },
        },
      });
    });
    const { initController } = await import('../initController');
    await initController();
    await settle();
    const view = [...mocks.renderSections.mock.calls]
      .reverse()
      .find(([options]) => options.section.sectionName === 'main')![0];
    view.onUpdateSubscription(view.section);
    await settle();
    expect(store.get().servicesInfoWidget.data.anticheburnetRunning).toBe(1);
    expect(store.get().servicesInfoWidget.data.singbox).toBe(1);
    expect(toggle).toHaveBeenLastCalledWith(
      'fkp_dashboard-page--service-stopped',
      false,
    );
    data = [section('main', 0), section('other', 0), section('new', 0)];
    await vi.advanceTimersByTimeAsync(10000);
    await settle();
    expect(
      store.get().sectionsWidget.data.map((item) => item.outbounds[0].latency),
    ).toEqual([42, 67, 0]);
    finishSubscription({
      success: true,
      data: { success: true, running: false },
    });
    await settle();
    expect(
      mocks.latencyTestStart.mock.calls.map((call) => call.slice(0, 3)),
    ).toEqual([
      ['group', 'main', 'main'],
      ['group', 'other', 'other'],
      ['group', 'new', 'new'],
    ]);
    expect(
      store.get().sectionsWidget.data.map((item) => item.outbounds[0].latency),
    ).toEqual([42, 67, 0]);
    // Zero from an unsuccessful probe must replace the cached 67ms as well.
    data = [section('main', 25), section('other', 0), section('new', 31)];
    finishLatency.forEach((finish) => finish());
    await settle();
    expect(
      store.get().sectionsWidget.data.map((item) => item.outbounds[0].latency),
    ).toEqual([25, 0, 31]);
    expect(store.get().sectionsWidget.latencyFetchingSections).toEqual({});
    store.set({ tabService: { current: '', all: [] } });
  });
});
