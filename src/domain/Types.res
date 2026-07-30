// Core domain types -- immutable, zero I/O imports.
// The domain layer has NO dependencies on adapters, ports, or Node built-ins.

/** RenderMode mapped from TS: "table" | "json" | "markdown" */
type renderMode = [#table | #json | #markdown]

/** Window mapped from TS literal union */
type windowType = [
  | #daily
  | #monthly
  | #rolling
  | #rolling5h
  | #rollingMcp
  | #rollingTokens
  | #rollingWeekly
]

/** AggregationStrategy mapped from TS snake_case to camelCase */
type aggregationStrategy = [#mostCritical | #max | #min | #mean | #median]

/** Immutable quota data for a single tracked resource. */
type quotaData = {
  id: string,
  providerName: string,
  used: float,
  /** null means unlimited */
  limit: option<float>,
  unit: string,
  reset: option<Date.t>,
  window: windowType,
  info: option<string>,
  /** Optional model identifier for providers that emit multiple rows per provider. */
  modelId: option<string>,
}

/** Snapshot returned by the fetch pipeline -- includes isolated per-provider failures. */
type quotaSnapshot = {
  fetchedAt: Date.t,
  data: array<quotaData>,
  /** Provider ID → error message. Present only when some providers failed. */
  errors: option<dict<string>>,
}

/** Single history point for ETTL regression. */
type historyPoint = {
  timestamp: float, // Unix ms
  used: float,
  limit: option<float>,
}

// -- helpers -----------------------------------------------------------------

let windowToString = (w: windowType): string => {
  switch w {
  | #daily => "daily"
  | #monthly => "monthly"
  | #rolling => "rolling"
  | #rolling5h => "rolling-5h"
  | #rollingMcp => "rolling-mcp"
  | #rollingTokens => "rolling-tokens"
  | #rollingWeekly => "rolling-weekly"
  }
}

let windowFromString = (s: string): option<windowType> => {
  switch s {
  | "daily" => Some(#daily)
  | "monthly" => Some(#monthly)
  | "rolling" => Some(#rolling)
  | "rolling-5h" => Some(#rolling5h)
  | "rolling-mcp" => Some(#rollingMcp)
  | "rolling-tokens" => Some(#rollingTokens)
  | "rolling-weekly" => Some(#rollingWeekly)
  | _ => None
  }
}

let renderModeToString = (m: renderMode): string => {
  switch m {
  | #table => "table"
  | #json => "json"
  | #markdown => "markdown"
  }
}

let renderModeFromString = (s: string): option<renderMode> => {
  switch s {
  | "table" => Some(#table)
  | "json" => Some(#json)
  | "markdown" => Some(#markdown)
  | _ => None
  }
}

let strategyToString = (s: aggregationStrategy): string => {
  switch s {
  | #mostCritical => "most_critical"
  | #max => "max"
  | #min => "min"
  | #mean => "mean"
  | #median => "median"
  }
}

let strategyFromString = (s: string): option<aggregationStrategy> => {
  switch s {
  | "most_critical" => Some(#mostCritical)
  | "max" => Some(#max)
  | "min" => Some(#min)
  | "mean" => Some(#mean)
  | "median" => Some(#median)
  | _ => None
  }
}


