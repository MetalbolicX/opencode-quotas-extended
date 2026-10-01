// src/Providers/CodingPlanParse/GoParser.res
// opencode Go official subscription usage API parser.

type quotaData = Domain.quotaData
type windowType = Domain.windowType

// Parses the official Go subscription usage response into stable window rows.
let parseUsage = (
  ~json: JSON.t,
  ~idPrefix: string,
  ~providerName: string,
): array<quotaData> => {
  switch json {
  | JSON.Object(root) =>
    switch Dict.get(root, "usage") {
    | Some(JSON.Object(usage)) =>
      let windows = [
        ("rolling", "5h", #rolling5h),
        ("weekly", "Weekly", #rollingWeekly),
        ("monthly", "Monthly", #monthly),
      ]
      windows->Belt.Array.keepMap(((key, label, windowType)) => {
        switch Dict.get(usage, key) {
        | Some(JSON.Object(windowDict)) =>
          let percent = switch Dict.get(windowDict, "percent") {
          | Some(value) => JsonNum.toNum(value)
          | None => None
          }
          switch percent {
          | Some(used) =>
            let info = `${providerName} ${label}`
            let entry: quotaData = {
              id: `${idPrefix}-${key}`,
              providerName: info,
              used,
              limit: Some(100.0),
              unit: "%",
              reset: Shared.parseIsoReset(windowDict, "resetsAt"),
              window: windowType,
              info: Some(info),
              modelId: None,
            }
            Some(entry)
          | None => None
          }
        | _ => None
        }
      })
    | _ => []
    }
  | _ => []
  }
}
