import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { store } from '../../../services/store.service';
import { startDashboardStats } from '../dashboardStats';

const mocks = vi.hoisted(() => ({
  getClashApiConnections: vi.fn(),
  subscribe: vi.fn(),
  unsubscribe: vi.fn(),
}));

vi.mock('../../../methods/shell', () => ({ AnticheburNETShellMethods: mocks }));
vi.mock('../../../methods/custom/getClashApiSecret', () => ({
  getClashApiSecret: async () => 'token & # +',
}));
vi.mock('../../../services/socket.service', () => ({ socket: mocks }));

function snapshot(uploadTotal: number, downloadTotal: number) {
  return {
    uploadTotal,
    downloadTotal,
    memory: 2048,
    connections: [{ id: 'sample' }],
  };
}

describe('dashboard statistics transport', () => {
  let stop: (() => void) | undefined;

  beforeEach(() => {
    vi.useFakeTimers({
      toFake: [
        'setTimeout',
        'clearTimeout',
        'setInterval',
        'clearInterval',
        'performance',
      ],
    });
    vi.resetAllMocks();
    mocks.subscribe.mockReturnValue(mocks.unsubscribe);
    store.reset();
  });

  afterEach(() => {
    stop?.();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('uses authenticated RPC over HTTPS and calculates rates between snapshots', async () => {
    vi.stubGlobal('window', {
      location: { hostname: 'router.test', protocol: 'https:' },
    });
    mocks.getClashApiConnections
      .mockResolvedValueOnce({ success: true, data: snapshot(300, 600) })
      .mockResolvedValueOnce({ success: true, data: snapshot(600, 1500) })
      .mockResolvedValueOnce({ success: true, data: snapshot(5, 10) });

    stop = startDashboardStats();
    await vi.advanceTimersByTimeAsync(0);
    expect(mocks.subscribe).not.toHaveBeenCalled();
    expect(store.get().trafficTotalWidget.data).toEqual({
      uploadTotal: 300,
      downloadTotal: 600,
    });
    expect(store.get().systemInfoWidget.data).toEqual({
      memory: 2048,
      connections: 1,
    });

    await vi.advanceTimersByTimeAsync(3000);
    expect(store.get().bandwidthWidget.data).toEqual({ up: 100, down: 300 });
    await vi.advanceTimersByTimeAsync(3000);
    expect(store.get().bandwidthWidget.data).toEqual({ up: 0, down: 0 });
    stop();
    await vi.advanceTimersByTimeAsync(9000);
    expect(mocks.getClashApiConnections).toHaveBeenCalledTimes(3);
  });

  it('keeps direct streams on HTTP and falls back when a stream disconnects', async () => {
    vi.stubGlobal('window', {
      location: { hostname: '[2001:db8::1]', protocol: 'http:' },
    });
    mocks.getClashApiConnections.mockResolvedValue({
      success: true,
      data: snapshot(30, 60),
    });
    stop = startDashboardStats();
    await vi.advanceTimersByTimeAsync(0);
    const [traffic, connections] = mocks.subscribe.mock.calls;
    expect(new URL(traffic[0]).searchParams.get('token')).toBe('token & # +');
    expect(new URL(connections[0]).pathname).toBe('/connections');
    traffic[1](JSON.stringify({ up: 1, down: 2 }));
    connections[1](JSON.stringify(snapshot(3, 6)));
    await vi.advanceTimersByTimeAsync(6000);
    expect(mocks.getClashApiConnections).not.toHaveBeenCalled();

    traffic[2]();
    connections[2]();
    await vi.advanceTimersByTimeAsync(0);
    expect(mocks.unsubscribe).toHaveBeenCalledTimes(2);
    expect(mocks.getClashApiConnections).toHaveBeenCalledOnce();
    expect(store.get().trafficTotalWidget.data).toEqual({
      uploadTotal: 30,
      downloadTotal: 60,
    });
  });

  it('falls back when the direct controller never sends data', async () => {
    vi.stubGlobal('window', {
      location: { hostname: 'router.test', protocol: 'http:' },
    });
    mocks.getClashApiConnections.mockResolvedValue({
      success: false,
      error: 'unavailable',
    });
    stop = startDashboardStats();
    await vi.advanceTimersByTimeAsync(3000);
    expect(mocks.unsubscribe).toHaveBeenCalledTimes(2);
    expect(mocks.getClashApiConnections).toHaveBeenCalledOnce();
    expect(store.get().trafficTotalWidget.failed).toBe(true);
  });
});
