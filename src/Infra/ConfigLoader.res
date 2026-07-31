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

// Generated schema module (produced by scripts/codegen.mjs)
// Schema.res lives in src/Infra/ConfigLoader/ (subdirectory of ConfigLoader),
// making it accessible as Schema (a submodule of ConfigLoader).

// Module-scoped compiled validator cache
let _validatorCache: ref<option<validator>> = ref(None)

let _getValidate = (): validator => {
  switch _validatorCache.contents {
  | Some(v) => v
  | None =>
    let inst = ajv()
    let _ = addFormats(inst)
    // Schema imported from generated ConfigLoader.Schema module (produced by scripts/codegen.mjs)
    let v = compile(inst, Schema.schema)
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

// ─── Typed JSON decoders ───────────────────────────────────────────────────────

let _optStr = (j: option<JSON.t>): option<string> =>
  switch j {
  | Some(JSON.String(s)) => Some(s)
  | _ => None
  }

let _optFloat = (j: option<JSON.t>): option<float> =>
  switch j {
  | Some(JSON.Number(n)) => Some(n)
  | _ => None
  }

let _objDict = (j: JSON.t): dict<JSON.t> =>
  switch j {
  | JSON.Object(d) => d
  | _ => Dict.make()
  }

let coerceToPartial = (_raw: JSON.t): partialConfig => {
  let d = _objDict(_raw)
  {
    displayMode: _optStr(Dict.get(d, "displayMode")),
    disabled: switch Dict.get(d, "disabled") {
    | Some(JSON.Array(arr)) => Some(arr->Array.map(v => switch v {
      | JSON.String(s) => s
      | _ => ""
      }))
    | _ => None
    },
    aggregatedGroups: %raw("_raw.aggregatedGroups === undefined ? undefined : _raw.aggregatedGroups"),
    historyMaxAgeHours: _optFloat(Dict.get(d, "historyMaxAgeHours")),
    pollingInterval: _optFloat(Dict.get(d, "pollingInterval")),
    predictionWindowMinutes: _optFloat(Dict.get(d, "predictionWindowMinutes")),
    predictionShortWindowMinutes: _optFloat(Dict.get(d, "predictionShortWindowMinutes")),
    // Booleans: JSON module has no Bool variant in this ReScript, use %raw
    showUnaggregated: %raw("_raw.showUnaggregated === undefined ? undefined : _raw.showUnaggregated"),
    show: %raw("_raw.show === undefined ? undefined : _raw.show"),
    filterByCurrentModel: %raw("_raw.filterByCurrentModel === undefined ? undefined : _raw.filterByCurrentModel"),
    // progressBar: use %raw to access nested fields since JSON module lacks Bool variant
    // Use == null (loose equality) so both null and undefined map to None (absent config)
    progressBar: %raw("_raw.progressBar == null ? undefined : _raw.progressBar"),
    credentials: Dict.get(d, "credentials"),
    anthropic: switch Dict.get(d, "anthropic") {
    | Some(JSON.Object(a)) => Some({orgId: _optStr(Dict.get(a, "orgId"))})
    | _ => None
    },
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
      JSON.parseOrThrow(depsRef.contents.readFileSync(configPath))
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
    let _ = switch Dict.get(_objDict(raw), "footer") {
    | Some(_) => warnFn(`config field 'footer' is deprecated and ignored`)
    | None => ()
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
        // Decode aggregatedGroups using typed JSON decoders
        let groupsOpt = switch Dict.get(_objDict(raw), "aggregatedGroups") {
        | Some(JSON.Object(g)) => Some(g)
        | _ => None
        }
        switch groupsOpt {
        | Some(g) =>
          let result: dict<aggregationGroup> = Dict.make()
          let groupKeys = Dict.keysToArray(g)
          let _ = groupKeys->Array.forEach(key => {
            let groupObj = switch Dict.get(g, key) {
            | Some(JSON.Object(go)) => go
            | _ => Dict.make()
            }
            let strategy = switch _optStr(Dict.get(groupObj, "strategy")) {
            | Some(s) => s
            | None => "max"
            }
            let members = switch Dict.get(groupObj, "members") {
            | Some(JSON.Array(arr)) =>
              arr->Array.map(v => switch v {
                | JSON.String(s) => s
                | _ => ""
              })
            | _ => []
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
