import type { AnticheburNET } from '../../types';

export function shouldApplyCompletedComponentActionResult(
  result: Pick<AnticheburNET.ComponentActionResult, 'action'>,
  notify: boolean,
) {
  return result.action !== 'check_update' || notify;
}
