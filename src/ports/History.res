// src/ports/History.res
// Canonical HistoryStore port — single source of truth for history persistence interface.
// Duplicated local shapes in ReportPipeline and JsonFileHistory MUST alias this port.

// Re-export the canonical historyPoint from domain types (Types.res:46)
type historyPoint = Domain.historyPoint

// Core history store contract — four spec-mandated methods, no bulk read in v1.
type historyStore = {
  append: (string, historyPoint) => promise<unit>,
  getHistory: (string, float) => promise<array<historyPoint>>,
  prune: float => promise<unit>,
  resetDetected: (string, historyPoint, float, option<float>) => bool,
}

// Noop store for environments that don't need durable history (e.g. tests).
let makeNoop = (): historyStore => {
  let append = (_id: string, _point: historyPoint): promise<unit> => Promise.resolve()
  let getHistory = (_id: string, _ms: float): promise<array<historyPoint>> => Promise.resolve([])
  let prune = (_ms: float): promise<unit> => Promise.resolve()
  let resetDetected = (
    _id: string,
    _prev: historyPoint,
    _used: float,
    _limit: option<float>,
  ): bool => false
  {append, getHistory, prune, resetDetected}
}
