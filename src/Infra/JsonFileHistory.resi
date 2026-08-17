// src/Infra/JsonFileHistory.resi
// HistoryStore adapter with debounced writes and reset detection.

type deps = {
  readFileSync: string => string,
  writeFileSync: (string, string) => unit,
  existsSync: string => bool,
  now: unit => float,
}

// Alias the canonical port type — single source of truth per design §2.
type historyStore = Ports.historyStore

type store = {
  ...historyStore,
  flushNow: unit => unit,
}

let make: (~debounceMs: float=?, string, deps) => store
