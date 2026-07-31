// src/Providers/MinimaxTests.res
// Tests for Minimax provider: createMinimaxProvider + parseMinimaxCli.
// Tests provider metadata (id, displayName, category, authStrategy) and
// mmx CLI parser reset-time computation.

open Minimax
open RescriptTest

autoBoot := false

// --- Tests --------------------------------------------------------------------

test("createMinimaxProvider returns provider with correct metadata", () => {
  let provider = createMinimaxProvider()
  assertion(~message="id is minimax", (a, b) => a == b, provider.id, "minimax")
  assertion(~message="displayName is Minimax Coding Plan", (a, b) => a == b, provider.displayName, "Minimax Coding Plan")
  assertion(~message="category is subscription", (a, b) => a == b, provider.category, "subscription")
  assertion(~message="authStrategy is api", (a, b) => a == b, provider.authStrategy, #api)
})

// mmx CLI stdout fixture — the human-readable table is omitted; the parser
// only needs the JSON blob starting at the "model_remains" key.
test("parseMinimaxCli populates reset from remains_time / weekly_remains_time", () => {
  let now = Date.now()
  // Anchor the fixture's "now" via the call so diffs are deterministic.
  // 9_600_000 ms = 2h40m remaining on the interval.
  // 214_848_000 ms ≈ 2d 11h 40m 48s remaining on the weekly.
  let intervalRemains = 9_600_000.0
  let weeklyRemains = 214_848_000.0
  let fixture = "...{\"model_remains\":[{\"start_time\":" ++ Belt.Float.toString(now) ++ ",\"end_time\":" ++ Belt.Float.toString(now +. intervalRemains) ++ ",\"remains_time\":" ++ Belt.Float.toString(intervalRemains) ++ ",\"current_interval_total_count\":0,\"current_interval_usage_count\":0,\"model_name\":\"general\",\"current_weekly_total_count\":0,\"current_weekly_usage_count\":0,\"weekly_start_time\":" ++ Belt.Float.toString(now) ++ ",\"weekly_end_time\":" ++ Belt.Float.toString(now +. weeklyRemains) ++ ",\"weekly_remains_time\":" ++ Belt.Float.toString(weeklyRemains) ++ ",\"current_interval_status\":1,\"current_interval_remaining_percent\":90,\"current_weekly_status\":1,\"current_weekly_remaining_percent\":80}],\"base_resp\":{\"status_code\":0,\"status_msg\":\"success\"}}"
  let entries = parseMinimaxCli(fixture)
  assertion(
    ~message="parseMinimaxCli returns 2 entries for general model",
    (a, b) => a == b,
    Array.length(entries),
    2,
  )
  // 5h row: reset ≈ now + 9_600_000 ms
  let fiveH = Belt.Array.getExn(entries, 0)
  assertion(~message="5h row has reset", (a, b) => a == b, Belt.Option.isSome(fiveH.reset), true)
  switch fiveH.reset {
  | Some(d) =>
    let diff = Date.getTime(d) -. now
    assertion(
      ~message="5h reset diff from now is >= 9_500_000 ms",
      (a, b) => a >= b,
      diff,
      9_500_000.0,
    )
    assertion(
      ~message="5h reset diff from now is <= 10_000_000 ms",
      (a, b) => a <= b,
      diff,
      10_000_000.0,
    )
  | None => ()
  }
  // Weekly row: reset ≈ now + 214_848_000 ms
  let weekly = Belt.Array.getExn(entries, 1)
  assertion(~message="weekly row has reset", (a, b) => a == b, Belt.Option.isSome(weekly.reset), true)
  switch weekly.reset {
  | Some(d) =>
    let diff = Date.getTime(d) -. now
    assertion(
      ~message="weekly reset diff from now is >= 214_000_000 ms",
      (a, b) => a >= b,
      diff,
      214_000_000.0,
    )
  | None => ()
  }
})

test("parseMinimaxCli falls back to None when remains_time is missing", () => {
  let fixture = "...{\"model_remains\":[{\"model_name\":\"general\",\"current_interval_remaining_percent\":90,\"current_weekly_remaining_percent\":80}]}"
  let entries = parseMinimaxCli(fixture)
  assertion(
    ~message="2 entries even without reset info",
    (a, b) => a == b,
    Array.length(entries),
    2,
  )
  let fiveH = Belt.Array.getExn(entries, 0)
  let weekly = Belt.Array.getExn(entries, 1)
  assertion(~message="5h reset is None when field missing", (a, b) => a == b, fiveH.reset, None)
  assertion(~message="weekly reset is None when field missing", (a, b) => a == b, weekly.reset, None)
})

// Run all tests
let () = runTests()
