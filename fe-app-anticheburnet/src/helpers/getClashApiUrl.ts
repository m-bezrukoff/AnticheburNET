function getWindowLocation(): Location | undefined {
  return typeof window !== 'undefined' ? window.location : undefined;
}

export function canUseDirectClashApi(): boolean {
  const location = getWindowLocation();

  return (
    typeof location?.hostname === 'string' &&
    location.hostname !== '' &&
    location.protocol === 'http:'
  );
}

export function getClashWsUrl(
  stream: 'connections' | 'traffic',
  secret: string,
): string {
  const { hostname } = window.location;

  const url = new URL(`ws://${hostname}:9090/${stream}`);
  url.searchParams.set('token', secret);
  return url.href;
}

export function getClashHttpUrl(): string {
  const { hostname } = window.location;

  return `http://${hostname}:9090`;
}

export function getClashUIUrl(): string {
  const { hostname } = window.location;

  return `http://${hostname}:9090/ui`;
}
