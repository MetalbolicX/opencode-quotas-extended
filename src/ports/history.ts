// HistoryStore — domain reads/persists history through this port (DIP).

import type { HistoryPoint } from "../domain/types.js";

export interface HistoryStore {
  /** Appends a new history point. Clears history first if reset is detected. */
  append(providerId: string, point: HistoryPoint): Promise<void>;

  /** Returns history points for a provider within the given time window (ms). */
  getHistory(providerId: string, windowMs: number): Promise<HistoryPoint[]>;

  /** Removes history points older than maxAgeMs. */
  prune(maxAgeMs: number): Promise<void>;

  /** Detects whether a reset has occurred between the previous point and new data. */
  resetDetected(providerId: string, prev: HistoryPoint, used: number, limit: number | null): boolean;
}
