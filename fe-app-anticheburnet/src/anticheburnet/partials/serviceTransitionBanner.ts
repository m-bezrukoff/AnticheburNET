import { renderLoaderCircleIcon24 } from '../../icons/renderLoaderCircleIcon24';
import { store } from '../services/store.service';
import { getServiceTransitionPhase } from './serviceTransitionBanner.state';

function transitionTitle(phase: ReturnType<typeof getServiceTransitionPhase>) {
  switch (phase) {
    case 'starting':
      return _('AnticheburNET is starting');
    case 'stopping':
      return _('AnticheburNET is stopping');
    case 'reloading':
      return _('AnticheburNET is applying configuration');
    default:
      return _('AnticheburNET is restarting');
  }
}

const mountedBanners = new WeakMap<HTMLElement, () => void>();

// The banner belongs to the map shell, outside the seven switchable panels.
// One live region and one subscription remain visible across every tab.
export function mountServiceTransitionBanner(root: HTMLElement) {
  mountedBanners.get(root)?.();
  const title = E('strong');
  const detail = E('span', { class: 'ac-service-transition__detail' });
  const icon = renderLoaderCircleIcon24();
  icon.querySelector('animateTransform')?.remove();
  icon.setAttribute('class', 'ac-service-transition__spinner');
  icon.setAttribute('aria-hidden', 'true');
  const banner = E(
    'div',
    {
      class: 'ac-service-transition',
      role: 'status',
      hidden: true,
    },
    [icon, E('div', { class: 'ac-service-transition__copy' }, [title, detail])],
  );
  banner.setAttribute('aria-live', 'polite');
  banner.setAttribute('aria-atomic', 'true');
  root.insertBefore(banner, root.firstChild);
  let previousPhase: ReturnType<typeof getServiceTransitionPhase> = null;
  const unsubscribe = store.subscribe((state) => {
    const phase = getServiceTransitionPhase(state);
    if (phase === previousPhase) return;
    previousPhase = phase;
    banner.hidden = phase === null;
    if (phase === null) {
      title.textContent = '';
      detail.textContent = '';
      return;
    }
    title.textContent = transitionTitle(phase);
    detail.textContent =
      phase === 'stopping'
        ? _('Waiting for the service to stop.')
        : _('Please wait. Connections may be briefly interrupted.');
  });
  const dispose = () => {
    unsubscribe();
    banner.remove();
    mountedBanners.delete(root);
  };
  mountedBanners.set(root, dispose);
  return dispose;
}
