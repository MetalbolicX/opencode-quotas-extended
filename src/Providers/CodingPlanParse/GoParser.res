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
        ("rolling", #rolling5h, SemanticLabels.Go5hRolling),
        ("weekly", #rollingWeekly, SemanticLabels.GoWeekly),
        ("monthly", #monthly, SemanticLabels.GoMonthly),
      ]
      windows->Belt.Array.keepMap(((key, windowType, concept)) => {
        switch Dict.get(usage, key) {
        | Some(JSON.Object(windowDict)) =>
          let percent = switch Dict.get(windowDict, "percent") {
          | Some(value) => JsonNum.toNum(value)
          | None => None
          }
          switch percent {
          | Some(used) =>
            // Same treatment as z.ai rows: brand · translated concept label.
            let branded = SemanticLabels.buildProviderName(providerName, concept)
            let label = SemanticLabels.getLabel(SemanticLabels.conceptKey(concept))
            let entry: quotaData = {
              id: `${idPrefix}-${key}`,
              providerName: branded,
              used,
              limit: Some(100.0),
              unit: "%",
              reset: Shared.parseIsoReset(windowDict, "resetsAt"),
              window: windowType,
              info: Some(label),
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
