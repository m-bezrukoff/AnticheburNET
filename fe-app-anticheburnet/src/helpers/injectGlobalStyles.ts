import { GlobalStyles } from '../styles';

const ANTICHEBURNET_GLOBAL_STYLES_ID = 'anticheburnet-global-styles';

export function injectGlobalStyles() {
  if (document.getElementById(ANTICHEBURNET_GLOBAL_STYLES_ID)) {
    return;
  }

  document.head.insertAdjacentHTML(
    'beforeend',
    `
        <style id="${ANTICHEBURNET_GLOBAL_STYLES_ID}">
          ${GlobalStyles}
        </style>
    `,
  );
}
