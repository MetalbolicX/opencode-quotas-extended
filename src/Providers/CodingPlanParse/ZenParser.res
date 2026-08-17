// src/Providers/CodingPlanParse/ZenParser.res
// Zen provider parser — windows array + credits object (fixed wildcard from plan 002).

// Zen provider parser — windows array + credits object (fixed wildcard from plan 002).
// No circular dep: defines types + uses windowMap directly.

type quotaData = Domain.quotaData
type windowType = Domain.windowType

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
        | Some(v) => JsonNum.toNum(v)
        | None => None
        }
        let limit = switch Dict.get(wDict, "limit") {
        | Some(v) => JsonNum.toNum(v)
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
        | Some(v) => JsonNum.toNum(v)
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
