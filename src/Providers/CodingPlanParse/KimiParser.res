// src/Providers/CodingPlanParse/KimiParser.res
// Kimi Code subscription usage API parser.
// Duplicates windowMap + parseIsoReset to avoid circular dep with facade.

type quotaData = Domain.quotaData
type windowType = Domain.windowType

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
  | Some(v) => JsonNum.toNum(v)
  | None => None
  }
  let limit = switch Dict.get(d, "limit") {
  | Some(v) => JsonNum.toNum(v)
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
    | Some(v) => JsonNum.toNum(v)
    | None => None
    }
    let limit = switch Dict.get(detailDict, "limit") {
    | Some(v) => JsonNum.toNum(v)
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
        | Some(v) => JsonNum.toNum(v)
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
