// src/Infra/JsonFileHistory.resi
// HistoryStore adapter with debounced writes and reset detection.

type deps = {
  readFileSync: string => string,
  writeFileSync: (string, string) => unit,
  existsSync: string => bool,
  now: unit => float,
}

type historyStore = {
  append: (string, Domain.historyPoint) => promise<unit>,
  getHistory: (string, float) => promise<array<Domain.historyPoint>>,
  prune: float => promise<unit>,
  resetDetected: (string, Domain.historyPoint, float, option<float>) => bool,
}

type store = {
  ...historyStore,
  flushNow: unit => unit,
}

let make: (~debounceMs: float=?, string, deps) => store
