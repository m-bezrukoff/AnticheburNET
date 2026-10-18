import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../../../../methods', () => ({
  AnticheburNETShellMethods: { checkFakeIP: vi.fn() },
  RemoteFakeIPMethods: { getFakeIpCheck: vi.fn(), getIpCheck: vi.fn() },
}));
vi.mock('../updateCheckStore', () => ({ updateCheckStore: vi.fn() }));

import {
  AnticheburNETShellMethods,
  RemoteFakeIPMethods,
} from '../../../../methods';
import { updateCheckStore } from '../updateCheckStore';
import { runFakeIPCheck } from '../runFakeIPCheck';

function router(fakeip = true, shared?: boolean) {
  vi.mocked(AnticheburNETShellMethods.checkFakeIP).mockResolvedValue({
    success: true,
    data: { fakeip, IP: '198.18.0.2', shared_public_ip_expected: shared },
  });
}

async function result() {
  await runFakeIPCheck();
  const calls = vi.mocked(updateCheckStore).mock.calls;
  return calls[calls.length - 1][0];
}

describe('FakeIP diagnostics with shared tunnel routing', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    router(true, true);
    vi.mocked(RemoteFakeIPMethods.getFakeIpCheck).mockResolvedValue({
      success: true,
      data: { fakeip: true, IP: '203.0.113.5' },
    });
    vi.mocked(RemoteFakeIPMethods.getIpCheck).mockResolvedValue({
      success: true,
      data: { fakeip: true, IP: '203.0.113.5' },
    });
  });

  it('passes equal public IPs when the configured tunnel is shared', async () => {
    const check = await result();
    expect(check.state).toBe('success');
    expect(check.items.every((item) => item.state === 'success')).toBe(true);
    expect(check.items[2].key).toBe(
      'Matching public IPs are expected with tunnel routing',
    );
  });

  it.each([false, undefined])(
    'keeps equal IPs inconclusive without confirmed shared routing (%s)',
    async (shared) => {
      router(true, shared);
      const check = await result();
      expect(check.state).toBe('warning');
      expect(check.items[2].state).toBe('warning');
    },
  );

  it('still passes distinct public IPs for selective routing', async () => {
    router(true, false);
    vi.mocked(RemoteFakeIPMethods.getIpCheck).mockResolvedValue({
      success: true,
      data: { fakeip: false, IP: '192.0.2.10' },
    });
    expect((await result()).state).toBe('success');
  });

  it('keeps router FakeIP failures visible with shared routing', async () => {
    router(false, true);
    const check = await result();
    expect(check.state).toBe('warning');
    expect(check.items[0].state).toBe('error');
  });

  it('keeps browser FakeIP failures visible with shared routing', async () => {
    vi.mocked(RemoteFakeIPMethods.getFakeIpCheck).mockResolvedValue({
      success: true,
      data: { fakeip: false, IP: '203.0.113.5' },
    });
    const check = await result();
    expect(check.state).toBe('warning');
    expect(check.items[1].state).toBe('error');
  });

  it('keeps failed control requests inconclusive', async () => {
    vi.mocked(RemoteFakeIPMethods.getIpCheck).mockResolvedValue({
      success: false,
      message: 'Timed out',
    });
    const check = await result();
    expect(check.state).toBe('warning');
    expect(check.items[2].key).toBe(
      'Could not compare FakeIP and control public IPs',
    );
  });

  it('keeps unavailable browser checks visible', async () => {
    vi.mocked(RemoteFakeIPMethods.getFakeIpCheck).mockResolvedValue({
      success: false,
      message: 'Timed out',
    });
    const check = await result();
    expect(check.state).toBe('warning');
    expect(check.items[1].state).toBe('warning');
    expect(check.items).toHaveLength(2);
  });

  it('does not accept empty public IPs as a successful comparison', async () => {
    vi.mocked(RemoteFakeIPMethods.getIpCheck).mockResolvedValue({
      success: true,
      data: { fakeip: true, IP: '' },
    });
    expect((await result()).state).toBe('warning');
  });
});
