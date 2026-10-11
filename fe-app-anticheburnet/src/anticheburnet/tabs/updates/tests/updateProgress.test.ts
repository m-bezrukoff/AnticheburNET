import { describe, expect, it } from 'vitest';
import { getUpdateProgressView } from '../updateProgress';

describe('update progress', () => {
  it('shows indeterminate checking until the backend reports an update', () => {
    expect(getUpdateProgressView().completed).toBeUndefined();
    expect(
      getUpdateProgressView({ stage: 'checking' }).completed,
    ).toBeUndefined();
  });
  it('counts completed stages and retains package/version details', () => {
    expect(
      getUpdateProgressView({
        stage: 'downloading',
        detail: 'backend.apk (2/3)',
        version: '1.0.7',
      }),
    ).toEqual({
      completed: 2,
      total: 8,
      label: 'Downloading packages',
      detail: 'backend.apk (2/3)',
      version: '1.0.7',
    });
  });
  it('does not claim completion while the service is starting', () => {
    const view = getUpdateProgressView({ stage: 'waiting' });
    expect(view.completed).toBe(7);
    expect(view.completed).toBeLessThan(view.total);
  });
});
