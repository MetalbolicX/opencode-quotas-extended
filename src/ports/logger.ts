// Logger — application logs through this port (DIP).

export interface Logger {
  debug(event: string, meta?: unknown): void;
  info(event: string, meta?: unknown): void;
  warn(event: string, meta?: unknown): void;
  error(event: string, meta?: unknown): void;
}
