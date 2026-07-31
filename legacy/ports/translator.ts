// Translator — all user-facing strings pass through this port (DIP).

export interface Translator {
  t(key: string, vars?: Record<string, string | number>): string;
}
