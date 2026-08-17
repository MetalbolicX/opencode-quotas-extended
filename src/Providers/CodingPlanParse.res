// src/Providers/CodingPlanParse.res
// Parses coding-plan provider JSON responses into QuotaData.
// Ported from src/adapters/providers/coding-plan-parse.ts.

// --- QuotaData helpers (local to this module) ----------------------------------

// Type re-export for internal use
type quotaData = Domain.quotaData
type windowType = Domain.windowType

// --- Helpers --------------------------------------------------------------------

// Converts any JSON value to option<float>, supporting numeric strings.
let toNum = (json: JSON.t): option<float> => {
  switch json {
  | JSON.Number(n) => Some(n)
  | JSON.String(s) =>
    let trimmed = String.trim(s)
    switch trimmed {
    | "" => None
    | _ =>
      let parsed = Float.fromString(trimmed)
      switch parsed {
      | Some(f) => Some(f)
      | None =>
        // Try stripping trailing % if present
        let withoutPct = switch trimmed->String.endsWith("%") {
        | true => trimmed->String.slice(~start=-1)->String.trim
        | false => trimmed
        }
        Float.fromString(withoutPct)
      }
    }
  | _ => None
  }
}

// Maps label strings to windowType variants.
let windowMap = (label: option<string>): windowType => {
  switch label {
  | Some("24h") => #daily
  | Some("30d") => #monthly
  | Some("5h") => #rolling5h
  | Some("1h") => #rolling1h
  | Some("1m") => #rollingMcp
  | Some("tokens") => #rollingTokens
  | Some("1w") => #rollingWeekly
  | _ => #rolling
  }
}

// --- parseZaiLimits -------------------------------------------------------------

// Parses a limit entry from the limits array, extracting usage and limit values.
// (Kept for internal use; not part of the public API.)
let parseLimitEntry = (
  acc: array<quotaData>,
  entry: JSON.t,
  idPrefix: string,
  providerName: string,
): array<quotaData> => {
  switch entry {
  | JSON.Object(dict) =>
    let used = switch Dict.get(dict, "used") {
    | Some(v) => toNum(v)
    | None => None
    }
    let limit = switch Dict.get(dict, "limit") {
    | Some(v) => toNum(v)
    | None => None
    }
    let label = switch Dict.get(dict, "label") {
    | Some(JSON.String(s)) => s
    | _ => ""
    }
    let window = windowMap(Some(label))
    let id = `${idPrefix}-${label->String.toLowerCase}`
    let info = `${providerName} ${label}`
    switch used {
    | Some(u) =>
      let newEntry: quotaData = {
        id,
        providerName: info,
        used: u,
        limit,
        unit: "%",
        reset: None,
        window,
        info: Some(info),
        modelId: None,
      }
      Belt.Array.push(acc, newEntry)->ignore
      acc
    | None => acc
    }
  | _ => acc
  }
}

// --- parseUsage -----------------------------------------------------------------

// Main parser entry point. Handles windows array + credits object.
let parseUsage = (
  ~json: JSON.t,
  ~idPrefix: string,
  ~providerName: string,
): array<quotaData> => {
  switch json {
  | JSON.Object(dict) =>
    let windows = switch Dict.get(dict, "windows") {
    | Some(JSON.Array(arr)) => arr
    | _ => []
    }
    let credits = Dict.get(dict, "credits")
    let entries: array<quotaData> = []

    // Parse window entries via reduce
    let entries = windows->Array.reduce(entries, (acc, w) => {
      switch w {
      | JSON.Object(wDict) =>
        let used = switch Dict.get(wDict, "used") {
        | Some(v) => toNum(v)
        | None => None
        }
        let limit = switch Dict.get(wDict, "limit") {
        | Some(v) => toNum(v)
        | None => None
        }
        switch used {
        | None => acc
        | Some(u) =>
          let label = switch Dict.get(wDict, "label") {
          | Some(JSON.String(s)) => s
          | _ => ""
          }
          let normalizedWindow = windowMap(Some(label))
          let info = `${providerName} ${label}`
          let id = `${idPrefix}-${label->String.toLowerCase}`
          let newEntry: quotaData = {
            id,
            providerName: info,
            used: u,
            limit,
            unit: "%",
            reset: None,
            window: normalizedWindow,
            info: Some(info),
            modelId: None,
          }
          Belt.Array.push(acc, newEntry)->ignore
          acc
        }
      | _ => acc
      }
    })

    // Handle credits
    switch credits {
    | Some(JSON.Object(cDict)) =>
      // unlimited field: only an explicit JSON true means unlimited credits
      // false, numbers, strings, null → NOT unlimited (credits row shown)
      let unlimited = switch Dict.get(cDict, "unlimited") {
      | Some(v) =>
        switch v {
        | JSON.Boolean(true) => true  // only explicit JSON true means unlimited
        | _ => false                // any other value (false, number, string) is not unlimited
        }
      | None => false
      }
      if !unlimited {
        let balance = switch Dict.get(cDict, "balance") {
        | Some(v) => toNum(v)
        | None => None
        }
        switch balance {
        | Some(bal) =>
          let creditEntry: quotaData = {
            id: `${idPrefix}-credits`,
            providerName: `${providerName} Credits`,
            used: bal,
            limit: None,
            unit: "credits",
            reset: None,
            window: #rolling,
            info: Some(`${providerName} Credits`),
            modelId: None,
          }
          Belt.Array.push(entries, creditEntry)->ignore
          entries
        | None => entries
        }
      } else {
        entries
      }
    | _ => entries
    }
  | _ => []
  }
}

// --- parseMonitorLimits ---------------------------------------------------------

// Alias for API parity -- parseMonitorLimits and parseUsage are semantically identical.
let parseMonitorLimits = parseUsage

// --- Helper: zaiWindow ---------------------------------------------------------

// Determines the window type for a Zai limit entry based on type and unit.
let zaiWindow = (
  limitType: string,
  unit: option<float>,
  isLitePlan: bool,
): windowType => {
  let t = limitType->String.toUpperCase
  if isLitePlan {
    if t === "TIME_LIMIT" && unit === Some(5.0) {
      #rollingMcp
    } else if t === "TOKENS_LIMIT" && unit === Some(3.0) {
      #rolling5h
    } else if t === "TOKENS_LIMIT" && unit === Some(6.0) {
      #rollingWeekly
    } else {
      #rolling
    }
  } else {
    if t === "TIME_LIMIT" {
      switch unit {
      | Some(5.0) => #rolling5h
      | Some(u) if u >= 168.0 => #rollingWeekly
      | _ => #rolling
      }
    } else if t === "MCP_LIMIT" {
      #rollingMcp
    } else if t === "TOKENS_LIMIT" {
      #rollingTokens
    } else {
      #rolling
    }
  }
}

// --- windowRank -----------------------------------------------------------------

// Ranks window types for priority ordering in display.
let windowRank = (w: windowType): int => {
  switch w {
  | #daily => 0
  | #monthly => 1
  | #rolling5h => 2
  | #rolling1h => 3
  | #rollingMcp => 4
  | #rollingTokens => 5
  | #rollingWeekly => 6
  | #rolling => 7
  }
}

// --- parseZaiLimits -------------------------------------------------------------

// Stable sort order for Z.Ai output: rolling-mcp → rolling-5h → rolling-weekly → fallback
let zaiSortRank = (w: windowType): int => {
  switch w {
  | #rollingMcp => 0
  | #rolling5h => 1
  | #rollingWeekly => 2
  | _ => 3
  }
}

// Helper: compute used percentage from a limit dict entry.
// Uses percentage as source of truth when finite; falls back to currentValue/usage.
let computeUsed = (limDict: Dict.t<JSON.t>): option<float> => {
  let pct = switch Dict.get(limDict, "percentage") {
  | Some(v) => toNum(v)
  | None => None
  }
  switch pct {
  | Some(p) =>
    switch Float.isFinite(p) {
    | true => Some(p)
    | false => None
    }
  | None =>
    let cv = switch Dict.get(limDict, "currentValue") {
    | Some(v) => toNum(v)
    | None => None
    }
    let u = switch Dict.get(limDict, "usage") {
    | Some(v) => toNum(v)
    | None => None
    }
    switch (cv, u) {
    | (Some(c), Some(uVal)) =>
      switch uVal !== 0.0 {
      | true => Some((c /. uVal) *. 100.0)
      | false => None
      }
    | _ => None
    }
  }
}

// Parses one limit dict into a QuotaData entry (or returns None).
let limitToQuota = (
  limDict: Dict.t<JSON.t>,
  idPrefix: string,
  providerName: string,
  isLitePlan: bool,
): option<quotaData> => {
  let type_ = switch Dict.get(limDict, "type") {
  | Some(JSON.String(s)) => s
  | _ => "LIMIT"
  }
  let unit = switch Dict.get(limDict, "unit") {
  | Some(v) => toNum(v)
  | None => None
  }
  let number = switch Dict.get(limDict, "number") {
  | Some(v) => toNum(v)
  | None => None
  }
  let resetMs = switch Dict.get(limDict, "nextResetTime") {
  | Some(v) => toNum(v)
  | None => None
  }
  let usedOpt = computeUsed(limDict)
  switch usedOpt {
  | None => None
  | Some(u) =>
    let normalizedWindow = zaiWindow(type_, unit, isLitePlan)
    let id = `${idPrefix}-${type_->String.toLowerCase}-${switch unit {
      | Some(v) => Belt.Float.toString(v)
      | None => "u"
    }}-${switch number {
      | Some(v) => Belt.Float.toString(v)
      | None => "n"
    }}`
    let hints: SemanticLabels.providerPayloadHints = {
      type_: Some(type_),
      unit: switch unit {
      | Some(v) => Some(Belt.Float.toString(v))
      | None => None
      },
      number,
      modelName: None,
      weekly: None,
      openaiVariant: None,
      geminiModel: None,
    }
    let baseConcept = SemanticLabels.enrichQuotaLabel(providerName, hints)
    let concept: SemanticLabels.enrichedLabel = if isLitePlan {
      if type_ === "TIME_LIMIT" && unit === Some(5.0) {
        {label: "MCP quota", concept: SemanticLabels.ZAiMcp}
      } else if type_ === "TOKENS_LIMIT" && unit === Some(3.0) {
        {label: "5h rolling window", concept: SemanticLabels.ZAi5HourRolling}
      } else if type_ === "TOKENS_LIMIT" && unit === Some(6.0) {
        {label: "Weekly quota", concept: SemanticLabels.ZAiWeeklyRolling}
      } else {
        baseConcept
      }
    } else {
      baseConcept
    }
    let providerBranded = SemanticLabels.buildProviderName(providerName, concept.concept)
    let resetDateOpt = switch resetMs {
    | Some(ms) =>
      switch ms > 0.0 {
      | true =>
        Some(Date.fromTime(ms))
      | false => None
      }
    | None => None
    }
    Some({
      id,
      providerName: providerBranded,
      used: u,
      limit: Some(100.0),
      unit: "%",
      reset: resetDateOpt,
      window: normalizedWindow,
      info: Some(concept.label),
      modelId: None,
    })
  }
}

// Parses Zai provider limit entries into QuotaData array.
// Schema: data.limits = Array<{ type, unit, number, usage, currentValue, remaining, percentage, nextResetTime, usageDetails }>
let parseZaiLimits = (
  ~json: JSON.t,
  ~idPrefix: string,
  ~providerName: string,
): array<quotaData> => {
  switch json {
  | JSON.Object(root) =>
    let limits = switch Dict.get(root, "data") {
    | Some(JSON.Object(dataDict)) =>
      switch Dict.get(dataDict, "limits") {
      | Some(JSON.Array(arr)) => arr
      | _ => []
      }
    | _ => []
    }
    // Lite plan encodes MCP / 5h / weekly on different type+unit combinations than
    // the full plan (no MCP_LIMIT, no TIME_LIMIT unit=168). Detect via data.level so
    // we can map the right human label to each row.
    let isLitePlan = switch Dict.get(root, "data") {
    | Some(JSON.Object(dataDict)) =>
      switch Dict.get(dataDict, "level") {
      | Some(JSON.String("lite")) => true
      | _ => false
      }
    | _ => false
    }
    let entries: array<quotaData> = Belt.Array.keepMap(limits, (entry) => {
      switch entry {
      | JSON.Object(limDict) => limitToQuota(limDict, idPrefix, providerName, isLitePlan)
      | _ => None
      }
    })
    // Stable sort: rolling-mcp → rolling-5h → rolling-weekly → fallback rows
    let _ = entries->Array.sort((a, b) => (zaiSortRank(a.window) - zaiSortRank(b.window) :> float))
    entries
  | _ => []
  }
}

// =============================================================================
// parseKimiUsages — Kimi Code subscription usage API parser
// =============================================================================

// Helper: parse ISO reset string to Date.t (Gemini.res idiom + zai ms>0.0 guard)
let parseIsoReset = (d: Dict.t<JSON.t>, key: string): option<Date.t> => {
  switch Dict.get(d, key) {
  | Some(JSON.String(s)) =>
    if s !== "" {
      let ms = Node.jsDateParse(s)
      switch ms > 0.0 {
      | true => Some(Date.fromTime(ms))
      | false => None
      }
    } else {
      None
    }
  | _ => None
  }
}

// Helper: maps Kimi window duration + timeUnit to (windowType, idSuffix)
// EXACT MATCH — no folding; pinned per REQ-K-2 spec
let kimiWindow = (duration: float, timeUnit: string, idPrefix: string): (windowType, string) => {
  switch timeUnit {
  | "TIME_UNIT_MINUTE" =>
    if duration == 300.0 {
      (#rolling5h, `${idPrefix}-5h`)
    } else {
      (#rolling, `${idPrefix}-${Belt.Float.toString(duration)}m`)
    }
  | "TIME_UNIT_HOUR" =>
    (#rolling1h, `${idPrefix}-1h`)
  | "TIME_UNIT_DAY" =>
    (#daily, `${idPrefix}-daily`)
  | "TIME_UNIT_WEEK" =>
    (#rollingWeekly, `${idPrefix}-10080m`)
  | _ =>
    (#rolling, `${idPrefix}-${Belt.Float.toString(duration)}${timeUnit}`)
  }
}

// Helper: convert summary usage dict to quotaData (or None if both used/limit absent)
let summaryToQuota = (
  d: Dict.t<JSON.t>,
  idPrefix: string,
  providerName: string,
): option<quotaData> => {
  let used = switch Dict.get(d, "used") {
  | Some(v) => toNum(v)
  | None => None
  }
  let limit = switch Dict.get(d, "limit") {
  | Some(v) => toNum(v)
  | None => None
  }
  // Both absent → skip
  switch (used, limit) {
  | (None, None) => None
  | (u, l) =>
    let effectiveUsed = switch u {
    | Some(uv) => uv
    | None => 0.0
    }
    let concept = SemanticLabels.enrichQuotaLabel(idPrefix, {
      type_: None,
      unit: None,
      number: None,
      modelName: None,
      weekly: Some(true),
      openaiVariant: None,
      geminiModel: None,
    })
    Some({
      id: `${idPrefix}-weekly`,
      providerName,
      used: effectiveUsed,
      limit: l,
      unit: "%",
      reset: parseIsoReset(d, "resetTime"),
      window: #rollingWeekly,
      info: Some(concept.label),
      modelId: None,
    })
  }
}

// Helper: convert a limit-row dict to quotaData (or None if detail non-object or both used/limit absent)
let limitRowToQuota = (
  d: Dict.t<JSON.t>,
  idPrefix: string,
  providerName: string,
): option<quotaData> => {
  switch Dict.get(d, "detail") {
  | Some(JSON.Object(detailDict)) =>
    let used = switch Dict.get(detailDict, "used") {
    | Some(v) => toNum(v)
    | None => None
    }
    let limit = switch Dict.get(detailDict, "limit") {
    | Some(v) => toNum(v)
    | None => None
    }
    // Both absent → skip
    switch (used, limit) {
    | (None, None) => None
    | (u, l) =>
      let windowDict = switch Dict.get(d, "window") {
      | Some(JSON.Object(w)) => Some(w)
      | _ => None
      }
      switch windowDict {
      | Some(wDict) =>
        let duration = switch Dict.get(wDict, "duration") {
        | Some(v) => toNum(v)
        | None => None
        }
        let timeUnit = switch Dict.get(wDict, "timeUnit") {
        | Some(JSON.String(t)) => t
        | _ => ""
        }
        switch duration {
        | Some(dur) =>
          let (window, id) = kimiWindow(dur, timeUnit, idPrefix)
          let effectiveUsed = switch u {
          | Some(uv) => uv
          | None => 0.0
          }
          let concept = SemanticLabels.enrichQuotaLabel(idPrefix, {
            type_: None,
            unit: None,
            number: None,
            modelName: None,
            weekly: Some(false),
            openaiVariant: None,
            geminiModel: None,
          })
          Some({
            id,
            providerName,
            used: effectiveUsed,
            limit: l,
            unit: "%",
            reset: parseIsoReset(detailDict, "resetTime"),
            window,
            info: Some(concept.label),
            modelId: None,
          })
        | None => None
        }
      | None => None
      }
    }
  | _ => None
  }
}

// Main entry point for Kimi Code subscription usage API
// Reads top-level `usage` (summary) and `limits[]` (per-window limits)
let parseKimiUsages = (
  ~json: JSON.t,
  ~idPrefix: string,
  ~providerName: string,
): array<quotaData> => {
  switch json {
  | JSON.Object(root) =>
    let summary = switch Dict.get(root, "usage") {
    | Some(JSON.Object(d)) => summaryToQuota(d, idPrefix, providerName)
    | _ => None
    }
    let limits = switch Dict.get(root, "limits") {
    | Some(JSON.Array(arr)) =>
      arr->Belt.Array.keepMap(entry => {
        switch entry {
        | JSON.Object(d) => limitRowToQuota(d, idPrefix, providerName)
        | _ => None
        }
      })
    | _ => []
    }
    switch summary {
    | Some(row) => [row, ...limits]
    | None => limits
    }
  | _ => []
  }
}
