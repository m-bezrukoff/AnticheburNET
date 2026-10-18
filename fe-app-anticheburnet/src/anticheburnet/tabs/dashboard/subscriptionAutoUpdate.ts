import { AnticheburNETShellMethods } from '../../methods';
import { showToast } from '../../../helpers/showToast';

export function mountSubscriptionAutoUpdate(container: HTMLElement) {
  let active = true;
  let enabled = false;
  const checkbox = E('input', {
    type: 'checkbox',
    id: 'dashboard-subscription-auto-update',
  }) as HTMLInputElement;
  checkbox.disabled = true;
  container.replaceChildren(
    E('label', { class: 'fkp_dashboard-page__subscription-auto-update' }, [
      checkbox,
      E('span', {}, _('Update subscriptions daily at 03:00 (router time)')),
    ]),
  );

  async function load() {
    try {
      const response = await AnticheburNETShellMethods.subscriptionAutoUpdate();
      if (!active) return;
      if (!response.success || typeof response.data?.enabled !== 'boolean') {
        throw new Error('settings unavailable');
      }
      enabled = response.data.enabled;
      checkbox.checked = enabled;
      checkbox.disabled = false;
    } catch {
      if (active)
        showToast(_('Failed to load automatic update settings'), 'error');
    }
  }

  checkbox.addEventListener('change', async () => {
    if (checkbox.disabled) return;
    const requested = checkbox.checked;
    checkbox.disabled = true;
    try {
      const response =
        await AnticheburNETShellMethods.subscriptionAutoUpdate(requested);
      if (!response.success || typeof response.data?.enabled !== 'boolean') {
        throw new Error('settings not saved');
      }
      enabled = response.data.enabled;
    } catch {
      if (active)
        showToast(_('Failed to save automatic update settings'), 'error');
    } finally {
      if (active) {
        checkbox.checked = enabled;
        checkbox.disabled = false;
      }
    }
  });
  void load();
  return () => {
    active = false;
  };
}
