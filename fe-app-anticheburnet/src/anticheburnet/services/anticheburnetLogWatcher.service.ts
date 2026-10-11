import { logger } from './logger.service';

type LogFetcher = () => Promise<string> | string;

interface AnticheburNETLogWatcherOptions {
  intervalMs?: number;
  onNewLog?: (line: string) => void;
  maxTrackedLines?: number;
}

export class AnticheburNETLogWatcher {
  private static instance: AnticheburNETLogWatcher;
  private fetcher?: LogFetcher;
  private onNewLog?: (line: string) => void;
  private intervalMs = 5000;
  private lastLines = new Set<string>();
  private maxTrackedLines = 500;
  private timer?: ReturnType<typeof setInterval>;
  private running = false;
  private paused = false;
  private checking = false;

  private constructor() {
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) this.pause();
        else this.resume();
      });
    }
  }

  static getInstance(): AnticheburNETLogWatcher {
    if (!AnticheburNETLogWatcher.instance) {
      AnticheburNETLogWatcher.instance = new AnticheburNETLogWatcher();
    }
    return AnticheburNETLogWatcher.instance;
  }

  init(fetcher: LogFetcher, options?: AnticheburNETLogWatcherOptions): void {
    this.fetcher = fetcher;
    this.onNewLog = options?.onNewLog;
    this.intervalMs = options?.intervalMs ?? 5000;
    this.maxTrackedLines = options?.maxTrackedLines ?? 500;
    this.lastLines = new Set();
    logger.info(
      '[AnticheburNETLogWatcher]',
      `initialized (interval: ${this.intervalMs}ms)`,
    );
  }

  private normalizeLines(raw: string): string[] {
    return raw.split('\n').filter(Boolean).slice(-this.maxTrackedLines);
  }

  async checkOnce(): Promise<void> {
    if (!this.fetcher) {
      logger.warn('[AnticheburNETLogWatcher]', 'fetcher not found');
      return;
    }

    if (this.paused) {
      logger.debug('[AnticheburNETLogWatcher]', 'skipped check — tab not visible');
      return;
    }

    if (this.checking) {
      logger.debug(
        '[AnticheburNETLogWatcher]',
        'skipped check — previous check is running',
      );
      return;
    }

    this.checking = true;

    try {
      const raw = await this.fetcher();
      const lines = this.normalizeLines(raw);

      for (const line of lines) {
        if (this.lastLines.has(line)) {
          continue;
        }

        this.lastLines.add(line);
        this.onNewLog?.(line);
      }

      if (this.lastLines.size > this.maxTrackedLines) {
        this.lastLines = new Set(
          Array.from(this.lastLines).slice(-this.maxTrackedLines),
        );
      }
    } catch (err) {
      logger.error('[AnticheburNETLogWatcher]', 'failed to read logs:', err);
    } finally {
      this.checking = false;
    }
  }

  start(): void {
    if (this.running) return;
    if (!this.fetcher) {
      logger.warn('[AnticheburNETLogWatcher]', 'attempted to start without fetcher');
      return;
    }

    this.running = true;
    void this.checkOnce();
    this.timer = setInterval(() => this.checkOnce(), this.intervalMs);
    logger.info(
      '[AnticheburNETLogWatcher]',
      `started (interval: ${this.intervalMs}ms)`,
    );
  }

  stop(): void {
    if (!this.running) return;
    this.running = false;
    if (this.timer) clearInterval(this.timer);
    logger.info('[AnticheburNETLogWatcher]', 'stopped');
  }

  pause(): void {
    if (!this.running || this.paused) return;
    this.paused = true;
    logger.info('[AnticheburNETLogWatcher]', 'paused (tab not visible)');
  }

  resume(): void {
    if (!this.running || !this.paused) return;
    this.paused = false;
    logger.info('[AnticheburNETLogWatcher]', 'resumed (tab active)');
    void this.checkOnce();
  }

  reset(): void {
    this.lastLines = new Set();
    this.checking = false;
    logger.info('[AnticheburNETLogWatcher]', 'log history reset');
  }
}
