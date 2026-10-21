'use strict';
'require baseclass';
'require fs';
'require uci';
'require ui';

if (typeof structuredClone !== 'function')
  globalThis.structuredClone = (obj) => JSON.parse(JSON.stringify(obj));

export { validateIP } from './validators/validateIp';
export { validateDomain } from './validators/validateDomain';
export { validateDNS } from './validators/validateDns';
export { validateUrl } from './validators/validateUrl';
export { validatePath } from './validators/validatePath';
export { validateSubnet } from './validators/validateSubnet';
export { bulkValidate } from './validators/bulkValidate';
export { validateOutboundJson } from './validators/validateOutboundJson';
export { validateProxyUrl } from './validators/validateProxyUrl';
export { parseValueList } from './helpers/parseValueList';
export { getProxyUrlName } from './helpers/getProxyUrlName';
export { injectGlobalStyles } from './helpers/injectGlobalStyles';
export { showToast } from './helpers/showToast';
export { getClashUIUrl } from './helpers/getClashApiUrl';
export { AnticheburNETShellMethods } from './anticheburnet/methods/shell';
export { coreService } from './anticheburnet/services/core.service';
export { mountServiceTransitionBanner } from './anticheburnet/partials/serviceTransitionBanner';
export { store } from './anticheburnet/services/store.service';
export { applyUiStateToStore } from './anticheburnet/services/uiState.service';
export { DashboardTab } from './anticheburnet/tabs/dashboard';
export { DiagnosticTab } from './anticheburnet/tabs/diagnostic';
export { MonitoringTab } from './anticheburnet/tabs/monitoring';
export { UpdatesTab } from './anticheburnet/tabs/updates';
export {
  BOOTSTRAP_DNS_SERVER_OPTIONS,
  DEFAULT_LATENCY_TEST_URL,
  DNS_SERVER_OPTIONS,
  DOMAIN_LIST_OPTIONS,
  LATENCY_TEST_URL_OPTIONS,
  ANTICHEBURNET_ACTION_PROVIDERS_AVAILABILITY_EVENT,
  ANTICHEBURNET_UCI_PACKAGE,
} from './constants';
