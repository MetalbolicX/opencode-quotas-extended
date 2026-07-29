// HistoryStore — domain reads/persists history through this port (DIP).

open Domain

type historyStore = {
  /** Appends a new history point. Clears history first if reset is detected. */
  append: (string, historyPoint) => promise<unit>,
  /** Returns history points for a provider within the given time window (ms). */
  getHistory: (string, float) => promise<array<historyPoint>>,
  /** Removes history points older than maxAgeMs. */
  prune: float => promise<unit>,
  /** Detects whether a reset has occurred between the previous point and new data. */
  resetDetected: (string, historyPoint, float, option<float>) => bool,
}
