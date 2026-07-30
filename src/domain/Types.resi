// Types.resi — public surface of the core domain type module.
// Exposes types and converter functions; factories are in DomainFixtures.
type renderMode = [#table | #json | #markdown]
type windowType = [
  | #daily
  | #monthly
  | #rolling
  | #rolling1h
  | #rolling5h
  | #rollingMcp
  | #rollingTokens
  | #rollingWeekly
]
type aggregationStrategy = [#mostCritical | #max | #min | #mean | #median]

type quotaData = {
  id: string,
  providerName: string,
  used: float,
  limit: option<float>,
  unit: string,
  reset: option<Date.t>,
  window: windowType,
  info: option<string>,
  modelId: option<string>,
}

type quotaSnapshot = {
  fetchedAt: Date.t,
  data: array<quotaData>,
  errors: option<dict<string>>,
}

type historyPoint = {
  timestamp: float,
  used: float,
  limit: option<float>,
}

let windowToString: windowType => string
let windowFromString: string => option<windowType>
let renderModeToString: renderMode => string
let renderModeFromString: string => option<renderMode>
let strategyToString: aggregationStrategy => string
let strategyFromString: string => option<aggregationStrategy>
