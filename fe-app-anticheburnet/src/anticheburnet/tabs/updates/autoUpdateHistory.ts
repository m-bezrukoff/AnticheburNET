import type { AnticheburNET } from '../../types';

export function getAutoUpdateHistoryText(
  lastRun: AnticheburNET.ReleaseAutoUpdateSettings['last_run'],
  loaded: boolean,
) {
  const prefix = _('Last automatic update:');
  if (!loaded) return `${prefix} ${_('Loading...')}`;
  if (!lastRun) return `${prefix} ${_('No recorded runs')}`;

  const status = {
    running: _('In progress'),
    updated: _('Updated'),
    latest: _('Already up to date'),
    failed: _('Failed'),
    interrupted: _('Interrupted'),
  }[lastRun.status];
  const version =
    lastRun.status === 'updated' && lastRun.version
      ? ` (${lastRun.version})`
      : '';
  return `${prefix} ${lastRun.local_time} · ${status}${version}`;
}
