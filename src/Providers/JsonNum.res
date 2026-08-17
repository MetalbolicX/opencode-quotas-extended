// src/Providers/JsonNum.res
// Shared number parsing from JSON values — canonical %-stripping version.
// Lifted from src/Providers/OpenAI.res (lines 11-32).
// Previously Anthropic.res and Minimax.res used a non-stripping variant that
// returned None for "85%"; unifying to %-stripping everywhere is an accepted
// additive behavior improvement (previously silent None → now Some).

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
