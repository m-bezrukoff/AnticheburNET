import type { AnticheburNET } from '../../types';

export function getUpdateProgressView(
  progress?: AnticheburNET.ComponentUpdateProgress,
) {
  const steps = [
    ['checking', 'Checking for updates'],
    ['resolving', 'Preparing update'],
    ['downloading', 'Downloading packages'],
    ['verifying', 'Verifying packages'],
    ['backup', 'Backing up settings'],
    ['installing', 'Installing update'],
    ['restarting', 'Restarting service'],
    ['waiting', 'Waiting for service'],
  ];
  const index = steps.findIndex(([stage]) => stage === progress?.stage);
  // The bar counts completed stages, not elapsed time or download bytes.
  return {
    label: steps[Math.max(0, index)][1],
    completed: index > 0 ? index : undefined,
    total: steps.length,
    detail: progress?.detail || '',
    version: progress?.version || '',
  };
}
