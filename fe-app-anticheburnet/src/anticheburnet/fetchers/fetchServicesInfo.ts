import { AnticheburNETShellMethods } from '../methods';
import { logger } from '../services/logger.service';
import { store } from '../services/store.service';
import { refreshRuntimeUiState } from '../services/runtimeUiState.service';
import { AnticheburNET } from '../types';

let latestServicesInfoRequestId = 0;

function getSettledMethodResponse<T>(
  scope: string,
  result: PromiseSettledResult<AnticheburNET.MethodResponse<T>>,
): AnticheburNET.MethodResponse<T> {
  if (result.status === 'fulfilled') {
    return result.value;
  }

  logger.error('[SERVICES_INFO]', `${scope} failed`, result.reason);

  return {
    success: false,
    error: result.reason instanceof Error ? result.reason.message : '',
  };
}

export async function fetchServicesInfo() {
  const requestId = ++latestServicesInfoRequestId;
  const uiState = await refreshRuntimeUiState({ force: true });

  if (requestId !== latestServicesInfoRequestId) {
    return;
  }

  if (uiState) {
    return uiState;
  }

  const [anticheburnetResult, singboxResult] = await Promise.allSettled([
    AnticheburNETShellMethods.getStatus(),
    AnticheburNETShellMethods.getSingBoxStatus(),
  ]);

  if (requestId !== latestServicesInfoRequestId) {
    return;
  }

  const anticheburnet = getSettledMethodResponse('getStatus', anticheburnetResult);
  const singbox = getSettledMethodResponse('getSingBoxStatus', singboxResult);
  const previousData = store.get().servicesInfoWidget.data;

  store.set({
    servicesInfoWidget: {
      loading: false,
      failed: !anticheburnet.success || !singbox.success,
      data: {
        singbox: singbox.success ? singbox.data.running : previousData.singbox,
        anticheburnetRunning: anticheburnet.success
          ? anticheburnet.data.running
          : previousData.anticheburnetRunning,
        anticheburnetEnabled: anticheburnet.success
          ? anticheburnet.data.enabled
          : previousData.anticheburnetEnabled,
        anticheburnetStatus: anticheburnet.success
          ? anticheburnet.data.status
          : previousData.anticheburnetStatus,
      },
    },
  });

  return undefined;
}
