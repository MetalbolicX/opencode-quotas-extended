// src/Infra/ConfigLoader.res
// Loads and validates .opencode/quotas.json using Ajv.

// ─── Logger type (redeclared locally — Logger.resi is interface-only) ──────────

type logger = {
  debug: (string, option<JSON.t>) => unit,
  info: (string, option<JSON.t>) => unit,
  warn: (string, option<JSON.t>) => unit,
  error: (string, option<JSON.t>) => unit,
}

// ─── Domain types ─────────────────────────────────────────────────────────────

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

// Mirrors QuotasConfig from TS (all fields required except where noted)
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

// Partial config mirrors QuotasConfig but all fields are option<t>
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

// ─── ajv FFI ─────────────────────────────────────────────────────────────────

type ajvInstance
type validator = JSON.t => bool

type ajvError = {
  instancePath: string,
  message: option<string>,
}

@new @module("ajv") external ajv: unit => ajvInstance = "default"
@module("ajv-formats") external addFormats: ajvInstance => ajvInstance = "default"
@send external compile: (ajvInstance, JSON.t) => validator = "compile"
@get external validatorErrors: validator => option<array<ajvError>> = "errors"

// Module-scoped compiled validator cache
let _validatorCache: ref<option<validator>> = ref(None)

let _getValidate = (): validator => {
  switch _validatorCache.contents {
  | Some(v) => v
  | None =>
    let inst = ajv()
    let _ = addFormats(inst)
    // Embedded JSON schema — copy of schemas/quotas.schema.json
    let schema: JSON.t = %raw(`{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://opencode.ai/schemas/quotas.json",
  "title": "opencode-quotas configuration",
  "type": "object",
  "additionalProperties": false,
  "definitions": {
    "displayMode": { "type": "string", "enum": ["table", "json", "markdown"] },
    "progressBar": {
      "type": "object", "additionalProperties": false,
      "properties": {
        "width": { "type": "integer", "minimum": 1, "maximum": 100, "default": 10 },
        "filledChar": { "type": "string", "default": "█" },
        "emptyChar": { "type": "string", "default": "." },
        "color": { "type": "boolean", "default": true },
        "gradients": { "type": "boolean", "default": false }
      }
    },
    "tableConfig": {
      "type": "object", "additionalProperties": false,
      "properties": {
        "columns": { "type": "array", "items": { "type": "string", "enum": ["name", "used", "limit", "percent", "reset", "status", "bar"] }, "default": ["name", "bar", "percent", "reset", "status"] },
        "header": { "type": "boolean", "default": true }
      }
    },
    "footerConfig": { "type": "object", "additionalProperties": false, "deprecated": true, "description": "DEPRECATED: footerConfig is no longer used.", "properties": { "show": { "type": "boolean", "default": true, "deprecated": true }, "compact": { "type": "boolean", "default": true } } },
    "aggregationStrategy": { "type": "string", "enum": ["most_critical", "max", "min", "mean", "median"] },
    "aggregatedGroups": {
      "type": "object",
      "additionalProperties": {
        "type": "object", "additionalProperties": false, "required": ["strategy", "members"],
        "properties": {
          "strategy": { "$ref": "#/definitions/aggregationStrategy" },
          "members": { "type": "array", "items": { "type": "string" }, "minItems": 1 }
        }
      }
    },
    "credentialEntry": {
      "oneOf": [
        { "type": "object", "additionalProperties": false, "required": ["type", "key"], "properties": { "type": { "const": "api" }, "key": { "type": "string", "minLength": 1 } } },
        { "type": "object", "additionalProperties": false, "required": ["type", "envVar"], "properties": { "type": { "const": "env" }, "envVar": { "type": "string", "minLength": 1 } } }
      ]
    },
    "credentials": { "type": "object", "additionalProperties": { "$ref": "#/definitions/credentialEntry" } }
  },
  "properties": {
    "displayMode": { "$ref": "#/definitions/displayMode" },
    "progressBar": { "$ref": "#/definitions/progressBar" },
    "table": { "$ref": "#/definitions/tableConfig" },
    "footer": { "$ref": "#/definitions/footerConfig", "deprecated": true, "description": "DEPRECATED: Footer config is no longer used." },
    "filterByCurrentModel": { "type": "boolean", "default": false },
    "disabled": { "type": "array", "items": { "type": "string" }, "default": [] },
    "credentials": { "$ref": "#/definitions/credentials" },
    "aggregatedGroups": { "$ref": "#/definitions/aggregatedGroups" },
    "historyMaxAgeHours": { "type": "integer", "minimum": 1, "maximum": 720, "default": 24 },
    "pollingInterval": { "type": "integer", "minimum": 0, "default": 0, "deprecated": true, "description": "DEPRECATED: pollingInterval is no longer used." },
    "predictionWindowMinutes": { "type": "integer", "minimum": 1, "maximum": 1440, "default": 60 },
    "predictionShortWindowMinutes": { "type": "integer", "minimum": 1, "maximum": 60, "default": 5 },
    "showUnaggregated": { "type": "boolean", "default": false },
    "show": { "type": "boolean", "default": true, "deprecated": true, "description": "DEPRECATED: show is no longer used." },
    "anthropic": { "type": "object", "additionalProperties": false, "properties": { "orgId": { "type": "string", "minLength": 1 } } }
  }
}`)
    let v = compile(inst, schema)
    _validatorCache := Some(v)
    v
  }
}

// ─── defaults ─────────────────────────────────────────────────────────────────

let defaults: quotasConfig = {
  displayMode: #table,
  disabled: [],
  aggregatedGroups: Dict.make(),
  historyMaxAgeHours: 24.0,
  pollingInterval: 0.0,
  predictionWindowMinutes: 60.0,
  predictionShortWindowMinutes: 5.0,
  showUnaggregated: false,
  show: Some(true),
  filterByCurrentModel: None,
  progressBar: {
    width: 10.0,
    filledChar: "█",
    emptyChar: ".",
    color: true,
    gradients: false,
  },
  credentials: None,
  anthropic: None,
}

// ─── Error type ───────────────────────────────────────────────────────────────

exception ConfigValidationError(string)

let raiseValidationError = (msg: string) => {
  throw(ConfigValidationError(msg))
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

let warnFnDefault = (msg: string) => {
  Node.consoleWarnStr(`[opencode-quotas] ${msg}`)
}

let coerceToPartial = (_raw: JSON.t): partialConfig => {
  {
    displayMode: %raw("_raw.displayMode === undefined ? undefined : _raw.displayMode"),
    disabled: %raw("_raw.disabled === undefined ? undefined : _raw.disabled"),
    aggregatedGroups: %raw("_raw.aggregatedGroups === undefined ? undefined : _raw.aggregatedGroups"),
    historyMaxAgeHours: %raw("_raw.historyMaxAgeHours === undefined ? undefined : _raw.historyMaxAgeHours"),
    pollingInterval: %raw("_raw.pollingInterval === undefined ? undefined : _raw.pollingInterval"),
    predictionWindowMinutes: %raw("_raw.predictionWindowMinutes === undefined ? undefined : _raw.predictionWindowMinutes"),
    predictionShortWindowMinutes: %raw("_raw.predictionShortWindowMinutes === undefined ? undefined : _raw.predictionShortWindowMinutes"),
    showUnaggregated: %raw("_raw.showUnaggregated === undefined ? undefined : _raw.showUnaggregated"),
    show: %raw("_raw.show === undefined ? undefined : _raw.show"),
    filterByCurrentModel: %raw("_raw.filterByCurrentModel === undefined ? undefined : _raw.filterByCurrentModel"),
    progressBar: %raw("_raw.progressBar === undefined ? undefined : _raw.progressBar"),
    credentials: %raw("_raw.credentials === undefined ? undefined : _raw.credentials"),
    anthropic: %raw("_raw.anthropic === undefined ? undefined : _raw.anthropic"),
  }
}

// ─── loadConfig ───────────────────────────────────────────────────────────────

type deps = {
  readFileSync: string => string,
  existsSync: string => bool,
  warnFn: string => unit,
}

let depsRef: ref<deps> = ref({
  readFileSync: Node.readFileSync,
  existsSync: Node.existsSync,
  warnFn: warnFnDefault,
})

let loadConfig = (
  ~configPath: string,
  ~_logger: option<logger>=?,
  (),
): quotasConfig => {
  let { existsSync, warnFn } = depsRef.contents

  if !existsSync(configPath) {
    defaults
  } else {
    let raw: JSON.t = try {
      %raw("(function(p, readFileSync) { return JSON.parse(readFileSync(p)) })(configPath, depsRef.contents.readFileSync)")
    } catch {
    | _exn => raiseValidationError(`Failed to read config file: ${configPath}: parse error`)
    }
    let validate = _getValidate()
    let valid = validate(raw)
    if !valid {
      let errMsg = switch validatorErrors(validate) {
      | Some(errs) =>
        errs->Array.map(e => {
          let msg = switch e.message {
          | Some(m) => m
          | None => "unknown"
          }
          `${e.instancePath} ${msg}`
        })->Array.joinUnsafe("; ")
      | None => "unknown error"
      }
      raiseValidationError(`Invalid quotas config: ${errMsg}`)
    }
    let partial = coerceToPartial(raw)
    let _ = switch partial.show {
    | Some(_) =>
      warnFn(`config field 'show' is deprecated and ignored`)
    | None => ()
    }
    let _ = switch partial.pollingInterval {
    | Some(_) =>
      warnFn(`config field 'pollingInterval' is deprecated and ignored`)
    | None => ()
    }
    let _ = switch %raw("raw && raw.footer !== undefined") {
    | true => warnFn(`config field 'footer' is deprecated and ignored`)
    | false => ()
    }
    let mergedPb = switch partial.progressBar {
    | Some(pb) =>
      let w = switch pb.width {
      | Some(v) => v
      | None => defaults.progressBar.width
      }
      let fc = switch pb.filledChar {
      | Some(v) => v
      | None => defaults.progressBar.filledChar
      }
      let ec = switch pb.emptyChar {
      | Some(v) => v
      | None => defaults.progressBar.emptyChar
      }
      let col = switch pb.color {
      | Some(v) => v
      | None => defaults.progressBar.color
      }
      let gr = switch pb.gradients {
      | Some(v) => v
      | None => defaults.progressBar.gradients
      }
      ({
        width: w,
        filledChar: fc,
        emptyChar: ec,
        color: col,
        gradients: gr,
      }: progressBar)
    | None => defaults.progressBar
    }
    {
      displayMode: switch partial.displayMode {
      | Some("json") => #json
      | Some("markdown") => #markdown
      | _ => #table
      },
      disabled: switch partial.disabled {
      | Some(a) => a
      | None => defaults.disabled
      },
      aggregatedGroups: {
        // Access raw JSON directly to correctly extract aggregatedGroups
        // (coerceToPartial incorrectly types array fields as dict<string>)
        let rawGroups: option<{..}> = %raw("raw && raw.aggregatedGroups === undefined ? undefined : raw.aggregatedGroups")
        switch rawGroups {
        | Some(groups) =>
          let result: dict<aggregationGroup> = Dict.make()
          let groupKeys = Dict.keysToArray(groups->Obj.magic)
          let _ = groupKeys->Array.forEach(key => {
            let groupObj = %raw("groups[key]")->Obj.magic
            let strategy = switch groupObj["strategy"]->Obj.magic {
            | Some(s) => s
            | None => "max"
            }
            let members: array<string> = switch groupObj["members"]->Obj.magic {
            | Some(arr) => arr
            | None => []
            }
            let _ = Dict.set(result, key, {strategy, members})
          })
          result
        | None => defaults.aggregatedGroups
        }
      },
      historyMaxAgeHours: switch partial.historyMaxAgeHours {
      | Some(h) => h
      | None => defaults.historyMaxAgeHours
      },
      pollingInterval: defaults.pollingInterval,
      predictionWindowMinutes: switch partial.predictionWindowMinutes {
      | Some(w) => w
      | None => defaults.predictionWindowMinutes
      },
      predictionShortWindowMinutes: switch partial.predictionShortWindowMinutes {
      | Some(w) => w
      | None => defaults.predictionShortWindowMinutes
      },
      showUnaggregated: switch partial.showUnaggregated {
      | Some(b) => b
      | None => defaults.showUnaggregated
      },
      show: None,
      filterByCurrentModel: partial.filterByCurrentModel,
      progressBar: mergedPb,
      credentials: partial.credentials,
      anthropic: switch partial.anthropic {
      | Some(a) => Some({ orgId: a.orgId })
      | None => None
      },
    }
  }
}

// ─── resolveAnthropicOrgId ───────────────────────────────────────────────────

let resolveAnthropicOrgId = (
  cfg: quotasConfig,
  ~auth: option<dict<dict<string>>>,
  ~env: option<dict<string>>,
  (),
): string => {
  // Priority 1: config.anthropic.orgId
  let fromCfg: option<string> = switch cfg.anthropic {
  | Some(a) =>
    switch a.orgId {
    | Some(id) if String.length(String.trim(id)) > 0 => Some(String.trim(id))
    | _ => None
    }
  | None => None
  }

  switch fromCfg {
  | Some(id) => id
  | None =>
    // Priority 2: auth.anthropic.orgId | auth.anthropic.org
    let fromAuth: option<string> = switch auth {
    | Some(a) =>
      switch Dict.get(a, "anthropic") {
      | Some(provider) =>
        switch Dict.get(provider, "orgId") {
        | Some(id) if String.length(String.trim(id)) > 0 => Some(String.trim(id))
        | _ =>
          switch Dict.get(provider, "org") {
          | Some(id) if String.length(String.trim(id)) > 0 => Some(String.trim(id))
          | _ => None
          }
        }
      | None => None
      }
    | None => None
    }

    switch fromAuth {
    | Some(id) => id
    | None =>
      // Priority 3: env.ANTHROPIC_ORG_ID
      let fromEnv: option<string> = switch env {
      | Some(e) =>
        switch Dict.get(e, "ANTHROPIC_ORG_ID") {
        | Some(id) if String.length(String.trim(id)) > 0 => Some(String.trim(id))
        | _ => None
        }
      | None => None
      }

      switch fromEnv {
      | Some(id) => id
      | None =>
        raiseValidationError(
          "Anthropic org_id missing: set anthropic.orgId in quotas.json, " ++
          "anthropic.orgId (or anthropic.org) in auth.json, " ++
          "or ANTHROPIC_ORG_ID env variable",
        )
      }
    }
  }
}
