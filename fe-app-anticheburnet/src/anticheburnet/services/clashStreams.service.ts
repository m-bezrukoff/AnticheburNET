import {
  canUseDirectClashApi,
  getClashWsUrl,
} from '../../helpers/getClashApiUrl';
import { getClashApiSecret } from '../methods/custom/getClashApiSecret';
import { socket } from './socket.service';

type Stream = 'traffic' | 'connections';
type StreamListener = (data: unknown) => void;
const CLASH_STREAM_TIMEOUT_MS = 3000;

export function startClashStreams(
  streams: Partial<Record<Stream, StreamListener>>,
  startFallback: () => void,
): () => void {
  if (!canUseDirectClashApi()) {
    startFallback();
    return () => {};
  }

  const entries = Object.entries(streams) as [Stream, StreamListener][];
  const waiting = new Set(entries.map(([stream]) => stream));
  const subscriptions: Array<() => void> = [];
  let stopped = false;
  const timer = setTimeout(fallback, CLASH_STREAM_TIMEOUT_MS);

  function stop() {
    stopped = true;
    clearTimeout(timer);
    for (const unsubscribe of subscriptions.splice(0)) unsubscribe();
  }

  function fallback() {
    if (!stopped) {
      stop();
      startFallback();
    }
  }

  void getClashApiSecret()
    .then((secret) => {
      if (stopped) return;

      for (const [stream, receive] of entries) {
        subscriptions.push(
          socket.subscribe(
            getClashWsUrl(stream, secret),
            (message) => {
              if (stopped) return;

              try {
                receive(JSON.parse(message));
              } catch {
                fallback();
                return;
              }

              waiting.delete(stream);
              if (!waiting.size) clearTimeout(timer);
            },
            () => queueMicrotask(fallback),
          ),
        );
      }
    })
    .catch(fallback);

  return stop;
}
