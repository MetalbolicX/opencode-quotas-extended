// Pure domain: immutable 5-group default set for the 5 coding-plan providers.
// Merged at the application layer with user config (user wins on id collision).
open Aggregation

// Five built-in aggregation groups — one per coding-plan provider.
// Strategy: max. ETTL-based "most_critical" is not wired in this release (the
// prediction module exists but requires accumulated history data).
let defaultAggregationGroups: array<aggregationGroup> = [
  {id: "opencode-zen-monthly", providerId: "zen", strategy: #max},
  {id: "opencode-go-monthly", providerId: "go", strategy: #max},
  {id: "zai-coding-plan-weekly", providerId: "zai", strategy: #max},
  {id: "kimi-daily", providerId: "kimi", strategy: #max},
  {id: "minimax-monthly", providerId: "minimax", strategy: #max},
]
