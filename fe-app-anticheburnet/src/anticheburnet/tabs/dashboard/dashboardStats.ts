import { AnticheburNETShellMethods } from '../../methods/shell';
import { startClashStreams } from '../../services/clashStreams.service';
import { store } from '../../services/store.service';

const STATS_POLL_INTERVAL_MS = 3000;

function counter(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new Error('Invalid Clash API counter');
  }
  return value;
}

function connectionsStats(data: unknown) {
  const payload = data as Record<string, unknown>;
  return {
    uploadTotal: counter(payload.uploadTotal),
    downloadTotal: counter(payload.downloadTotal),
    memory: counter(payload.memory),
    connections: Array.isArray(payload.connections)
      ? payload.connections.length
      : 0,
  };
}

function applyConnections(data: ReturnType<typeof connectionsStats>) {
  const { downloadTotal, uploadTotal, memory, connections } = data;
  store.set({
    trafficTotalWidget: {
      loading: false,
      failed: false,
      data: { downloadTotal, uploadTotal },
    },
    systemInfoWidget: {
      loading: false,
      failed: false,
      data: { memory, connections },
    },
  });
}

function setBandwidth(up: number, down: number) {
  store.set({
    bandwidthWidget: { loading: false, failed: false, data: { up, down } },
  });
}

export function startDashboardStats(): () => void {
  let stopped = false;
  let polling = false;
  let timer: ReturnType<typeof setInterval> | undefined;
  let previous: { up: number; down: number; time: number } | undefined;

  async function poll() {
    if (polling || stopped) return;
    polling = true;
    try {
      const result = await AnticheburNETShellMethods.getClashApiConnections();
      if (stopped) return;
      if (!result.success) throw new Error(result.error);

      const stats = connectionsStats(result.data);
      applyConnections(stats);
      const time = performance.now();
      const seconds = previous ? (time - previous.time) / 1000 : 0;
      if (previous && seconds > 0) {
        setBandwidth(
          Math.max(0, stats.uploadTotal - previous.up) / seconds,
          Math.max(0, stats.downloadTotal - previous.down) / seconds,
        );
      }
      previous = { up: stats.uploadTotal, down: stats.downloadTotal, time };
    } catch {
      if (stopped) return;
      previous = undefined;
      const { bandwidthWidget, trafficTotalWidget, systemInfoWidget } =
        store.get();
      store.set({
        bandwidthWidget: { ...bandwidthWidget, loading: false, failed: true },
        trafficTotalWidget: {
          ...trafficTotalWidget,
          loading: false,
          failed: true,
        },
        systemInfoWidget: { ...systemInfoWidget, loading: false, failed: true },
      });
    } finally {
      polling = false;
    }
  }

  const stopStreams = startClashStreams(
    {
      traffic: (data) => {
        const { up, down } = data as Record<string, unknown>;
        setBandwidth(counter(up), counter(down));
      },
      connections: (data) => applyConnections(connectionsStats(data)),
    },
    () => {
      void poll();
      timer = setInterval(() => void poll(), STATS_POLL_INTERVAL_MS);
    },
  );

  return () => {
    stopped = true;
    stopStreams();
    clearInterval(timer);
  };
}
