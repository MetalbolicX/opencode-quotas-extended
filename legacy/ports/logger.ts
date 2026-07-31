// Logger — application logs through this port (DIP).

export interface Logger {
  debug(event: string, meta?: unknown): void;
  info(event: string, meta?: unknown): void;
  warn(event: string, meta?: unknown): void;
  error(event: string, meta?: unknown): void;
}

/** Silent no-op logger — used as the default when no logger is injected. */
export const noopLogger: Logger = Object.freeze({
  debug() {},
  info() {},
  warn() {},
  error() {},
});
