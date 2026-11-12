import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { socket } from '../socket.service';

class FakeWebSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static instances: FakeWebSocket[] = [];

  readyState = FakeWebSocket.CONNECTING;
  private listeners = new Map<string, Array<(event: Event) => void>>();

  constructor(_url: string) {
    FakeWebSocket.instances.push(this);
  }

  addEventListener(type: string, listener: (event: Event) => void) {
    const listeners = this.listeners.get(type) || [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  emit(type: string, event: Event = new Event(type)) {
    for (const listener of this.listeners.get(type) || []) {
      listener(event);
    }
  }

  close() {
    this.emit('close');
  }
}

describe('socket service', () => {
  const subscriptions: Array<() => void> = [];

  beforeEach(() => {
    vi.useFakeTimers();
    FakeWebSocket.instances = [];
    vi.stubGlobal('WebSocket', FakeWebSocket);
  });

  afterEach(() => {
    for (const unsubscribe of subscriptions.splice(0)) unsubscribe();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('keeps the initial subscriber when the first connection fails', () => {
    const onError = vi.fn();

    subscriptions.push(socket.subscribe('ws://router.test', vi.fn(), onError));
    FakeWebSocket.instances[0].emit('error');

    expect(onError).toHaveBeenCalledOnce();
  });

  it('reconnects after unexpected closure and preserves subscribers', () => {
    const listener = vi.fn();

    subscriptions.push(socket.subscribe('ws://router.test', listener));
    FakeWebSocket.instances[0].emit('close');
    vi.advanceTimersByTime(1000);

    expect(FakeWebSocket.instances).toHaveLength(2);
    FakeWebSocket.instances[1].emit('message', {
      data: 'restored',
    } as MessageEvent);
    expect(listener).toHaveBeenCalledWith('restored');
  });

  it('uses 1, 2, then 5 second reconnect delays', () => {
    subscriptions.push(socket.subscribe('ws://router.test', vi.fn()));

    FakeWebSocket.instances[0].emit('close');
    vi.advanceTimersByTime(1000);
    FakeWebSocket.instances[1].emit('close');
    vi.advanceTimersByTime(2000);
    FakeWebSocket.instances[2].emit('close');
    vi.advanceTimersByTime(5000);

    expect(FakeWebSocket.instances).toHaveLength(4);
  });

  it('does not reconnect after manual disconnect', () => {
    const unsubscribe = socket.subscribe('ws://router.test', vi.fn());
    unsubscribe();
    vi.advanceTimersByTime(10000);

    expect(FakeWebSocket.instances).toHaveLength(1);
  });

  it('keeps other subscribers and ignores events from the previous socket', () => {
    const url = 'ws://router.test/connections?token=example';
    const first = vi.fn();
    const second = vi.fn();
    const stopFirst = socket.subscribe(url, first);
    const stopSecond = socket.subscribe(url, second);
    const oldSocket = FakeWebSocket.instances[0];
    const event = { data: 'sample' } as MessageEvent;

    stopFirst();
    oldSocket.emit('message', event);
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledOnce();
    stopSecond();

    const next = vi.fn();
    const onError = vi.fn();
    subscriptions.push(socket.subscribe(url, next, onError));
    oldSocket.emit('message', event);
    oldSocket.emit('error');
    expect(next).not.toHaveBeenCalled();
    expect(onError).not.toHaveBeenCalled();

    FakeWebSocket.instances[1].emit('message', event);
    expect(next).toHaveBeenCalledWith('sample');
  });
});
