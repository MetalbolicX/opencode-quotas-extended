// src/Providers/CodingPlanParse/ZaiParser.res
// Z.ai provider parser — limitToQuota (~82 lines, 8 nesting levels, moved verbatim).

type quotaData = Domain.quotaData
type windowType = Domain.windowType

// Helper: zaiWindow ---------------------------------------------------------

// Determines the window type for a Zai limit entry based on type and unit.
let zaiWindow = (
  limitType: string,
  unit: option<float>,
  usesUnitCodes: bool,
): windowType => {
  let t = limitType->String.toUpperCase
  if usesUnitCodes {
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
  | Some(v) => JsonNum.toNum(v)
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
    | Some(v) => JsonNum.toNum(v)
    | None => None
    }
    let u = switch Dict.get(limDict, "usage") {
    | Some(v) => JsonNum.toNum(v)
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
  usesUnitCodes: bool,
): option<quotaData> => {
  let type_ = switch Dict.get(limDict, "type") {
  | Some(JSON.String(s)) => s
  | _ => "LIMIT"
  }
  let unit = switch Dict.get(limDict, "unit") {
  | Some(v) => JsonNum.toNum(v)
  | None => None
  }
  let number = switch Dict.get(limDict, "number") {
  | Some(v) => JsonNum.toNum(v)
  | None => None
  }
  let resetMs = switch Dict.get(limDict, "nextResetTime") {
  | Some(v) => JsonNum.toNum(v)
  | None => None
  }
  let usedOpt = computeUsed(limDict)
  switch usedOpt {
  | None => None
  | Some(u) =>
    let normalizedWindow = zaiWindow(type_, unit, usesUnitCodes)
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
    let concept: SemanticLabels.enrichedLabel = if usesUnitCodes {
      if type_ === "TIME_LIMIT" && unit === Some(5.0) {
        {label: "MCP quota", concept: SemanticLabels.ZAiMcp}
      } else if type_ === "TOKENS_LIMIT" && unit === Some(3.0) {
        {label: "5h rolling window", concept: SemanticLabels.ZAi5HourRolling}
      } else if type_ === "TOKENS_LIMIT" && unit === Some(6.0) {
        {label: "Weekly limit", concept: SemanticLabels.ZAiWeeklyRolling}
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
    // lite, pro, and max plans encode MCP / 5h / weekly on different type+unit
    // combinations than the full plan (no MCP_LIMIT, no TIME_LIMIT unit=168):
    // TIME_LIMIT u5 = MCP, TOKENS_LIMIT u3 = 5h, TOKENS_LIMIT u6 = weekly.
    // Unknown or missing levels keep the conservative full-plan mapping.
    let usesUnitCodes = switch Dict.get(root, "data") {
    | Some(JSON.Object(dataDict)) =>
      switch Dict.get(dataDict, "level") {
      | Some(JSON.String("lite")) => true
      | Some(JSON.String("pro")) => true
      | Some(JSON.String("max")) => true
      | _ => false
      }
    | _ => false
    }
    let entries: array<quotaData> = Belt.Array.keepMap(limits, (entry) => {
      switch entry {
      | JSON.Object(limDict) => limitToQuota(limDict, idPrefix, providerName, usesUnitCodes)
      | _ => None
      }
    })
    // Stable sort: rolling-mcp → rolling-5h → rolling-weekly → fallback rows
    let _ = entries->Array.sort((a, b) => (zaiSortRank(a.window) - zaiSortRank(b.window) :> float))
    entries
  | _ => []
  }
}
