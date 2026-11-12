import { logger } from './logger.service';

type Listener = (data: string) => void;
type ErrorListener = (error: Event | string) => void;

function logEndpoint(url: string): string {
  return url.split(/[?#]/, 1)[0];
}

class SocketManager {
  private static instance: SocketManager;
  private sockets = new Map<string, WebSocket>();
  private listeners = new Map<string, Set<Listener>>();
  private errorListeners = new Map<string, Set<ErrorListener>>();
  private reconnectAttempts = new Map<string, number>();
  private reconnectTimers = new Map<string, ReturnType<typeof setTimeout>>();

  private constructor() {}

  static getInstance(): SocketManager {
    if (!SocketManager.instance) {
      SocketManager.instance = new SocketManager();
    }
    return SocketManager.instance;
  }

  private connect(url: string): void {
    if (this.sockets.has(url)) return;

    let ws: WebSocket;

    try {
      ws = new WebSocket(url);
    } catch (err) {
      logger.error(
        '[SOCKET]',
        `failed to construct WebSocket for ${logEndpoint(url)}`,
      );
      this.triggerError(url, err instanceof Event ? err : String(err));
      this.scheduleReconnect(url);
      return;
    }

    this.sockets.set(url, ws);
    if (!this.listeners.has(url)) this.listeners.set(url, new Set());
    if (!this.errorListeners.has(url)) this.errorListeners.set(url, new Set());

    ws.addEventListener('open', () => {
      if (this.sockets.get(url) !== ws) return;
      this.reconnectAttempts.delete(url);
      logger.info('[SOCKET]', 'Connected to', logEndpoint(url));
    });

    ws.addEventListener('message', (event) => {
      if (this.sockets.get(url) !== ws || typeof event.data !== 'string')
        return;
      const handlers = this.listeners.get(url);
      if (handlers) {
        for (const handler of handlers) {
          try {
            handler(event.data);
          } catch (err) {
            logger.error(
              '[SOCKET]',
              `Handler error for ${logEndpoint(url)}:`,
              err,
            );
          }
        }
      }
    });

    ws.addEventListener('close', () => {
      if (this.sockets.get(url) !== ws) return;
      this.sockets.delete(url);
      logger.warn('[SOCKET]', `Disconnected: ${logEndpoint(url)}`);
      this.triggerError(url, 'Connection closed');
      this.scheduleReconnect(url);
    });

    ws.addEventListener('error', (err) => {
      if (this.sockets.get(url) !== ws) return;
      logger.error('[SOCKET]', `Socket error for ${logEndpoint(url)}`);
      this.triggerError(url, err);
    });
  }

  subscribe(
    url: string,
    listener: Listener,
    onError?: ErrorListener,
  ): () => void {
    if (!this.errorListeners.has(url)) {
      this.errorListeners.set(url, new Set());
    }
    if (onError) {
      this.errorListeners.get(url)?.add(onError);
    }

    if (!this.listeners.has(url)) {
      this.listeners.set(url, new Set());
    }
    this.listeners.get(url)?.add(listener);

    if (!this.sockets.has(url)) {
      this.connect(url);
    }

    return () => this.unsubscribe(url, listener, onError);
  }

  private unsubscribe(
    url: string,
    listener: Listener,
    onError?: ErrorListener,
  ): void {
    this.listeners.get(url)?.delete(listener);
    if (onError) {
      this.errorListeners.get(url)?.delete(onError);
    }
    if (this.listeners.get(url)?.size === 0) {
      this.disconnect(url);
    }
  }

  private disconnect(url: string): void {
    const ws = this.sockets.get(url);
    this.clearReconnect(url);
    this.sockets.delete(url);
    this.listeners.delete(url);
    this.errorListeners.delete(url);
    if (ws) ws.close();
  }

  private triggerError(url: string, err: Event | string): void {
    const handlers = this.errorListeners.get(url);
    if (handlers) {
      for (const cb of handlers) {
        try {
          cb(err);
        } catch (e) {
          logger.error(
            '[SOCKET]',
            `Error handler threw for ${logEndpoint(url)}:`,
            e,
          );
        }
      }
    }
  }

  private scheduleReconnect(url: string): void {
    if (
      this.reconnectTimers.has(url) ||
      (this.listeners.get(url)?.size || 0) === 0
    ) {
      return;
    }

    const attempt = this.reconnectAttempts.get(url) || 0;
    const delays = [1000, 2000, 5000];
    const delay = delays[Math.min(attempt, delays.length - 1)];
    this.reconnectAttempts.set(url, attempt + 1);
    this.reconnectTimers.set(
      url,
      setTimeout(() => {
        this.reconnectTimers.delete(url);
        if ((this.listeners.get(url)?.size || 0) > 0) this.connect(url);
      }, delay),
    );
  }

  private clearReconnect(url: string): void {
    const timer = this.reconnectTimers.get(url);
    if (timer) clearTimeout(timer);
    this.reconnectTimers.delete(url);
    this.reconnectAttempts.delete(url);
  }
}

export const socket = SocketManager.getInstance();
