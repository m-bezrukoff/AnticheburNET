import { describe, expect, it } from 'vitest';
import { getAutoUpdateHistoryText } from '../autoUpdateHistory';

describe('automatic update history', () => {
  it('does not invent a run before history has loaded or when it is absent', () => {
    expect(getAutoUpdateHistoryText(null, false)).toBe(
      'Last automatic update: Loading...',
    );
    expect(getAutoUpdateHistoryText(null, true)).toBe(
      'Last automatic update: No recorded runs',
    );
  });

  it.each([
    ['running', 'In progress'],
    ['latest', 'Already up to date'],
    ['failed', 'Failed'],
    ['interrupted', 'Interrupted'],
  ] as const)('shows the router time and %s status', (status, label) => {
    expect(
      getAutoUpdateHistoryText(
        {
          at: 1792026000,
          local_time: '2026-10-15 04:00:00',
          status,
          version: '',
        },
        true,
      ),
    ).toBe(`Last automatic update: 2026-10-15 04:00:00 · ${label}`);
  });

  it('shows the installed version only after an actual update', () => {
    expect(
      getAutoUpdateHistoryText(
        {
          at: 1792026000,
          local_time: '2026-10-15 04:00:00',
          status: 'updated',
          version: '1.0.16',
        },
        true,
      ),
    ).toBe('Last automatic update: 2026-10-15 04:00:00 · Updated (1.0.16)');
  });
});
