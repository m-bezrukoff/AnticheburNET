import type { StoreType } from '../services/store.service';

type TransitionState = Pick<
  StoreType,
  'servicesInfoWidget' | 'diagnosticsActions' | 'updatesActions'
>;

export function getServiceTransitionPhase(state: TransitionState) {
  const status = state.servicesInfoWidget.data.anticheburnetStatus;
  const actions = state.diagnosticsActions;
  if (status === 'reloading') return 'reloading';
  if (status === 'restarting' || actions.restart.loading) return 'restarting';
  if (status === 'starting' || actions.start.loading) return 'starting';
  if (status === 'stopping' || actions.stop.loading) return 'stopping';
  if (
    Object.values(state.updatesActions).some(
      (action) => action.loading && action.progress?.stage === 'restarting',
    )
  ) {
    return 'restarting';
  }
  return null;
}
