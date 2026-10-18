import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ settings: vi.fn(), toast: vi.fn() }));
vi.mock('../../../methods', () => ({
  AnticheburNETShellMethods: { subscriptionAutoUpdate: mocks.settings },
}));
vi.mock('../../../../helpers/showToast', () => ({ showToast: mocks.toast }));
import { mountSubscriptionAutoUpdate } from '../subscriptionAutoUpdate';

type Input = {
  checked: boolean;
  disabled: boolean;
  change?: () => Promise<void>;
};

describe('Dashboard daily subscription updates', () => {
  let input: Input;
  const container = { replaceChildren: vi.fn() } as unknown as HTMLElement;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal('E', (tag: string) => {
      if (tag !== 'input') return {};
      input = {
        checked: false,
        disabled: false,
        addEventListener: (_: string, callback: () => Promise<void>) => {
          input.change = callback;
        },
      } as Input;
      return input;
    });
  });

  it('loads the persisted choice and saves a toggle immediately', async () => {
    mocks.settings.mockResolvedValue({
      success: true,
      data: { enabled: true },
    });
    mountSubscriptionAutoUpdate(container);
    expect(input.disabled).toBe(true);
    await vi.waitFor(() => expect(input.disabled).toBe(false));
    expect(input.checked).toBe(true);
    input.checked = false;
    mocks.settings.mockResolvedValue({
      success: true,
      data: { enabled: false },
    });
    await input.change?.();
    expect(mocks.settings).toHaveBeenLastCalledWith(false);
    expect(input.checked).toBe(false);
  });

  it('restores the displayed choice when saving fails', async () => {
    mocks.settings.mockResolvedValue({
      success: true,
      data: { enabled: true },
    });
    mountSubscriptionAutoUpdate(container);
    await vi.waitFor(() => expect(input.disabled).toBe(false));
    mocks.settings.mockRejectedValue(new Error('network'));
    input.checked = false;
    await input.change?.();
    expect(input.checked).toBe(true);
    expect(input.disabled).toBe(false);
    expect(mocks.toast).toHaveBeenCalledWith(
      'Failed to save automatic update settings',
      'error',
    );
  });

  it('ignores a late load response after leaving Dashboard', async () => {
    let resolve!: (response: unknown) => void;
    mocks.settings.mockReturnValue(
      new Promise((done) => {
        resolve = done;
      }),
    );
    const unmount = mountSubscriptionAutoUpdate(container);
    unmount();
    resolve({ success: true, data: { enabled: true } });
    await Promise.resolve();
    expect(input.checked).toBe(false);
    expect(input.disabled).toBe(true);
  });
});
