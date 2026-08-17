// src/ports/History.resi
// Interface for the canonical HistoryStore port.

// Canonical historyPoint — mirrors Domain.Types.historyPoint
type historyPoint = Domain.historyPoint

// Four-method port contract. No bulk read in v1 (per REQ-E-2-2).
// Concrete adapters (JsonFileHistory) extend this with flushNow at the store level.
type historyStore = {
  append: (string, historyPoint) => promise<unit>,
  getHistory: (string, float) => promise<array<historyPoint>>,
  prune: float => promise<unit>,
  resetDetected: (string, historyPoint, float, option<float>) => bool,
}

let makeNoop: unit => historyStore
