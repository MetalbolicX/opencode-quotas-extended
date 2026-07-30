// src/Providers/CodingPlanParse.res
// Parses coding-plan provider JSON responses into QuotaData.
// Ported from src/adapters/providers/coding-plan-parse.ts.
// Uses SemanticLabels FFI via open SemanticLabels.

// --- QuotaData helpers (local to this module) ----------------------------------

// Type re-export for internal use
type quotaData = QuotaData.quotaData
type windowType = QuotaData.windowType

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
  | Some("5h") => #\"rolling-5h"
  | Some("1h") => #\"rolling-1h"
  | Some("1m") => #\"rolling-mcp"
  | Some("tokens") => #\"rolling-tokens"
  | Some("1w") => #\"rolling-weekly"
  | _ => #rolling
  }
}

// --- parseZaiLimits -------------------------------------------------------------

// Parses a limit entry from the limits array, extracting usage and limit values.
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
      // unlimited field: check if it's truthy
      // In JSON, a truthy value means unlimited is set
      let unlimited = switch Dict.get(cDict, "unlimited") {
      | Some(v) =>
        // For JSON, we check if the value is explicitly true
        switch v {
        | _ => true  // Any non-null value in the unlimited field means it's set
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
      #\"rolling-mcp"
    } else if t === "TOKENS_LIMIT" && unit === Some(3.0) {
      #\"rolling-5h"
    } else if t === "TOKENS_LIMIT" && unit === Some(6.0) {
      #\"rolling-weekly"
    } else {
      #rolling
    }
  } else {
    if t === "TIME_LIMIT" {
      switch unit {
      | Some(5.0) => #\"rolling-5h"
      | Some(u) if u >= 168.0 => #\"rolling-weekly"
      | _ => #rolling
      }
    } else if t === "MCP_LIMIT" {
      #\"rolling-mcp"
    } else if t === "TOKENS_LIMIT" {
      #\"rolling-tokens"
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
  | #\"rolling-5h" => 2
  | #\"rolling-1h" => 3
  | #\"rolling-mcp" => 4
  | #\"rolling-tokens" => 5
  | #\"rolling-weekly" => 6
  | #rolling => 7
  }
}

// --- parseZaiLimits -------------------------------------------------------------

// Parses Zai provider limit entries into QuotaData array.
let parseZaiLimits = (
  ~json: JSON.t,
  ~idPrefix: string,
  ~providerName: string,
  ~isLitePlan: bool,
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
    let entries = []
    limits->Array.reduce(entries, (acc, entry) => {
      switch entry {
      | JSON.Object(limDict) =>
        let t = switch Dict.get(limDict, "kind") {
        | Some(JSON.String(s)) => s
        | _ => ""
        }
        let unit = switch Dict.get(limDict, "unit") {
        | Some(v) => toNum(v)
        | None => None
        }
        let used = switch Dict.get(limDict, "used") {
        | Some(v) => toNum(v)
        | None => None
        }
        let limit = switch Dict.get(limDict, "limit") {
        | Some(v) => toNum(v)
        | None => None
        }
        let label = switch Dict.get(limDict, "label") {
        | Some(JSON.String(s)) => s
        | _ => ""
        }
        let normalizedWindow = zaiWindow(t, unit, isLitePlan)
        let info = `${providerName} ${label}`
        let id = `${idPrefix}-${label->String.toLowerCase}`
        switch used {
        | Some(u) =>
          let newEntry: quotaData = {
            id,
            providerName: info,
            used: u,
            limit,
            unit: switch normalizedWindow {
            | #\"rolling-tokens" => "tokens"
            | #\"rolling-mcp" => "minutes"
            | _ => "%"
            },
            reset: None,
            window: normalizedWindow,
            info: Some(info),
            modelId: None,
          }
          Belt.Array.push(acc, newEntry)->ignore
          acc
        | None => acc
        }
      | _ => acc
      }
    })
  | _ => []
  }
}
