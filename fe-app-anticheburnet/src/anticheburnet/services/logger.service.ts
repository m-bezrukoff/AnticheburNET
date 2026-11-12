type LogLevel = 'debug' | 'info' | 'warn' | 'error';

class Logger {
  private format(level: LogLevel, ...args: unknown[]): string {
    return `[${level.toUpperCase()}] ${args.join(' ')}`;
  }

  private push(level: LogLevel, ...args: unknown[]): void {
    const message = this.format(level, ...args);

    switch (level) {
      case 'error':
        console.error(message);
        break;
      case 'warn':
        console.warn(message);
        break;
      case 'info':
        console.info(message);
        break;
      default:
        console.log(message);
    }
  }

  debug(...args: unknown[]): void {
    this.push('debug', ...args);
  }

  info(...args: unknown[]): void {
    this.push('info', ...args);
  }

  warn(...args: unknown[]): void {
    this.push('warn', ...args);
  }

  error(...args: unknown[]): void {
    this.push('error', ...args);
  }
}

export const logger = new Logger();
