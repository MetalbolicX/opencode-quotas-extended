// src/Providers/CodingPlanParse/Shared.res
// Shared helpers for all CodingPlanParse submodules.

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
