// src/Infra/ConfigLoader.resi
// Loads and validates .opencode/quotas.json using Ajv.

type logger = {
  debug: (string, option<JSON.t>) => unit,
  info: (string, option<JSON.t>) => unit,
  warn: (string, option<JSON.t>) => unit,
  error: (string, option<JSON.t>) => unit,
}

type progressBar = {
  width: float,
  filledChar: string,
  emptyChar: string,
  color: bool,
  gradients: bool,
}

type progressBarPartial = {
  width: option<float>,
  filledChar: option<string>,
  emptyChar: option<string>,
  color: option<bool>,
  gradients: option<bool>,
}

type aggregationGroup = {
  strategy: string,
  members: array<string>,
}

type anthropicConfig = {
  orgId: option<string>,
}

type anthropicConfigPartial = {
  orgId: option<string>,
}

type quotasConfig = {
  displayMode: Domain.renderMode,
  disabled: array<string>,
  aggregatedGroups: dict<aggregationGroup>,
  historyMaxAgeHours: float,
  pollingInterval: float,
  predictionWindowMinutes: float,
  predictionShortWindowMinutes: float,
  showUnaggregated: bool,
  show: option<bool>,
  filterByCurrentModel: option<bool>,
  progressBar: progressBar,
  credentials: option<JSON.t>,
  anthropic: option<anthropicConfig>,
}

type partialConfig = {
  displayMode: option<string>,
  disabled: option<array<string>>,
  aggregatedGroups: option<dict<dict<string>>>,
  historyMaxAgeHours: option<float>,
  pollingInterval: option<float>,
  predictionWindowMinutes: option<float>,
  predictionShortWindowMinutes: option<float>,
  showUnaggregated: option<bool>,
  show: option<bool>,
  filterByCurrentModel: option<bool>,
  progressBar: option<progressBarPartial>,
  credentials: option<JSON.t>,
  anthropic: option<anthropicConfigPartial>,
}

let loadConfig: (~configPath: string, ~_logger: logger=?, unit) => quotasConfig

let resolveAnthropicOrgId: (quotasConfig, ~auth: option<dict<dict<string>>>, ~env: option<dict<string>>, unit) => string

let defaults: quotasConfig

// Test dependency injection
type deps = {
  readFileSync: string => string,
  existsSync: string => bool,
  warnFn: string => unit,
}

let depsRef: ref<deps>

exception ConfigValidationError(string)

