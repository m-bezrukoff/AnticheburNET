// language=CSS
import { ANTICHEBURNET_UCI_PACKAGE as ANTICHEBURNET_CBI_PREFIX } from '../../../constants';

export const styles = `
#cbi-${ANTICHEBURNET_CBI_PREFIX}-updates-_mount_node {
    display: block;
    margin: 0;
    padding: 0;
}

#cbi-${ANTICHEBURNET_CBI_PREFIX}-updates-_mount_node > .cbi-value-title {
    display: none;
}

#cbi-${ANTICHEBURNET_CBI_PREFIX}-updates-_mount_node > .cbi-value-field {
    display: block;
    float: none;
    margin-left: 0;
    width: 100%;
    min-width: 0;
    box-sizing: border-box;
}

#cbi-${ANTICHEBURNET_CBI_PREFIX}-updates > h3 {
    display: none;
}

.fkp_updates-page {
    width: 100%;
}

.fkp_updates-page__components {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    width: 100%;
    max-width: 100%;
    overflow-x: auto;
}

.fkp_updates-page__components-main {
    display: flex;
    flex: 1 1 0;
    flex-direction: column;
    gap: 10px;
    min-width: 260px;
}

.fkp_updates-page__components-optional {
    display: flex;
    flex: 0 0 auto;
    gap: 10px;
    margin-left: auto;
    align-items: flex-start;
}

.fkp_updates-page__components-optional > .fkp_updates-page__component {
    width: max-content;
    flex: 0 0 auto;
    white-space: nowrap;
}

.fkp_updates-page__components-optional .fkp_updates-page__component__header,
.fkp_updates-page__components-optional .fkp_updates-page__component__actions-main,
.fkp_updates-page__components-optional .fkp_updates-page__component__info-value--latest {
    flex-wrap: nowrap;
}

.fkp_updates-page__component {
    border: 2px var(--background-color-low, lightgray) solid;
    border-radius: 4px;
    padding: 10px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-width: 0;
    box-sizing: border-box;
}

.fkp_updates-page__auto-update {
    display: flex;
    align-items: center;
    gap: 7px;
    cursor: pointer;
    color: var(--text-color-high);
    font-size: 13px;
    line-height: 1.4;
}
.fkp_updates-page__auto-update input {
    margin: 0;
    flex: 0 0 auto;
}

.fkp_updates-page__auto-update-history {
    color: var(--text-color-medium, #888);
    font-size: 12px;
    line-height: 1.4;
    overflow-wrap: anywhere;
}

.fkp_updates-page__component__header {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    border-bottom: 1px var(--background-color-low, lightgray) solid;
    padding-bottom: 8px;
    margin-bottom: 2px;
}

.fkp_updates-page__component__title {
    color: var(--text-color-high);
    font-size: 16px;
    font-weight: bold;
    line-height: 1.2;
}

.fkp_updates-page__component__header-version {
    color: var(--text-color-medium, #888);
    font-size: 13px;
    font-weight: normal;
}

.fkp_updates-page__component__details {
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.fkp_updates-page__component__info-row {
    display: flex;
    justify-content: flex-start;
    align-items: center;
    min-height: 24px;
    gap: 8px;
    white-space: nowrap;
}

.fkp_updates-page__component__info-label {
    color: var(--text-color-medium, #888);
    font-size: 12px;
}

.fkp_updates-page__component__info-value {
    color: var(--text-color-high, #000);
    font-weight: 500;
    font-size: 13px;
    text-align: left;
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    overflow-wrap: anywhere;
}

.fkp_updates-page__component__info-value--latest {
    flex-wrap: wrap;
    justify-content: flex-start;
}

.fkp_updates-page__component__release-version-link {
    color: var(--link-color, #3498db) !important;
    text-decoration: underline;
    font-weight: bold;
}

.fkp_updates-page__component__release-version-link:hover {
    color: var(--link-color-dark, #2980b9) !important;
}

.fkp_updates-page__component__actions {
    display: flex;
    flex-direction: column;
    gap: 10px;
    margin-top: auto;
}

.fkp_updates-page__component__actions--with-details {
    border-top: 1px var(--background-color-low, lightgray) solid;
    padding-top: 10px;
}

.fkp_updates-page__component__actions-main {
    display: flex;
    justify-content: flex-start;
    align-items: center;
    flex-wrap: wrap;
    gap: 6px;
}

.fkp_updates-page__component__variants {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 4px;
}

.fkp_updates-page__component__variants-title {
    font-size: 11px;
    font-weight: bold;
    color: var(--text-color-medium, gray);
}

.fkp_updates-page__component__variants-buttons {
    display: flex;
    flex-wrap: nowrap;
    gap: 6px;
}

.fkp_updates-page__progress {
    display: flex;
    flex-direction: column;
    gap: 6px;
    max-width: 380px;
    min-width: 0;
}
.fkp_updates-page__progress progress {
    width: 100%;
    height: 10px;
    accent-color: var(--link-color, #3498db);
}
.fkp_updates-page__progress-label { color: var(--text-color-high); }
.fkp_updates-page__progress-detail {
    color: var(--text-color-medium, #888);
    font-size: 12px;
    overflow-wrap: anywhere;
}
`;
