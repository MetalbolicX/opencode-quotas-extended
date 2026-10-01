// src/Providers/GoParserTests.res
// Tests for the opencode Go official usage API parser.

open CodingPlanParse
open RescriptTest

autoBoot := false

let first = (arr: array<'a>): 'a => Belt.Array.getExn(arr, 0)

let window = (pairs: array<(string, JSON.t)>): JSON.t => JSON.Object(Dict.fromArray(pairs))
let usageJson = (windows: array<(string, JSON.t)>): JSON.t =>
  JSON.Object(Dict.fromArray([("usage", JSON.Object(Dict.fromArray(windows)))]))
let validWindow = (percent: float, resetsAt: option<string>): JSON.t => {
  let resetPair = switch resetsAt {
  | Some(value) => [("resetsAt", JSON.String(value))]
  | None => []
  }
  window([("status", JSON.String("ok")), ("percent", JSON.Number(percent)), ...resetPair])
}
let parse = (json: JSON.t): array<Domain.quotaData> =>
  parseGoUsage(~json, ~idPrefix="go", ~providerName="Go")

// --- parseGoUsage tests ---------------------------------------------------------

test("parseGoUsage parses all windows in rolling, weekly, monthly order", () => {
  let json = usageJson([
    ("rolling", validWindow(19.5, Some("2026-08-24T18:22:00.952Z"))),
    ("weekly", validWindow(0.0, Some("2026-08-31T00:00:00.952Z"))),
    ("monthly", validWindow(42.0, Some("2026-09-24T12:11:13.952Z"))),
  ])
  let result = parse(json)
  assertion(~message="Should return 3 entries", (a, b) => a == b, result->Array.length, 3)
  assertion(~message="First id is rolling", (a, b) => a == b, Belt.Array.getExn(result, 0).id, "go-rolling")
  assertion(~message="Second id is weekly", (a, b) => a == b, Belt.Array.getExn(result, 1).id, "go-weekly")
  assertion(~message="Third id is monthly", (a, b) => a == b, Belt.Array.getExn(result, 2).id, "go-monthly")
})

test("parseGoUsage maps windows and labels", () => {
  let result = parse(usageJson([
    ("rolling", validWindow(19.5, None)),
    ("weekly", validWindow(20.0, None)),
    ("monthly", validWindow(30.0, None)),
  ]))
  assertion(~message="rolling maps to rolling5h", (a, b) => a == b, Belt.Array.getExn(result, 0).window, #rolling5h)
  assertion(~message="weekly maps to rollingWeekly", (a, b) => a == b, Belt.Array.getExn(result, 1).window, #rollingWeekly)
  assertion(~message="monthly maps to monthly", (a, b) => a == b, Belt.Array.getExn(result, 2).window, #monthly)
  assertion(~message="rolling info", (a, b) => a == b, Belt.Array.getExn(result, 0).info, Some("Go 5h"))
  assertion(~message="weekly info", (a, b) => a == b, Belt.Array.getExn(result, 1).info, Some("Go Weekly"))
  assertion(~message="monthly info", (a, b) => a == b, Belt.Array.getExn(result, 2).info, Some("Go Monthly"))
})

test("parseGoUsage maps percentages, limit, unit, and provider names", () => {
  let result = parse(usageJson([("rolling", validWindow(19.5, None))]))
  let entry = first(result)
  assertion(~message="used equals percent", (a, b) => a == b, entry.used, 19.5)
  assertion(~message="limit is 100 percent", (a, b) => a == b, entry.limit, Some(100.0))
  assertion(~message="unit is percent", (a, b) => a == b, entry.unit, "%")
  assertion(~message="providerName has the 5h label", (a, b) => a == b, entry.providerName, "Go 5h")
  assertion(~message="modelId is absent", (a, b) => a == b, entry.modelId, None)
})

test("parseGoUsage parses resetsAt and ignores missing resetsAt", () => {
  let result = parse(usageJson([
    ("rolling", validWindow(19.5, Some("1970-01-01T00:00:01Z"))),
    ("weekly", validWindow(10.0, None)),
  ]))
  assertion(~message="ISO reset is present", (a, b) => a == b, Belt.Array.getExn(result, 0).reset->Option.isSome, true)
  assertion(
    ~message="ISO reset has expected epoch milliseconds",
    (a, b) => a == b,
    switch Belt.Array.getExn(result, 0).reset { | Some(date) => Date.getTime(date) | None => -1.0 },
    1000.0,
  )
  assertion(~message="missing reset is None", (a, b) => a == b, Belt.Array.getExn(result, 1).reset, None)
})

test("parseGoUsage skips a window without numeric percent", () => {
  let result = parse(usageJson([("weekly", window([("status", JSON.String("ok"))]))]))
  assertion(~message="Only the missing-percent window is skipped", (a, b) => a == b, result->Array.length, 0)
  let partial = parse(usageJson([
    ("rolling", window([("status", JSON.String("ok"))])),
    ("weekly", validWindow(15.0, None)),
  ]))
  assertion(~message="Only weekly remains", (a, b) => a == b, partial->Array.length, 1)
  assertion(~message="Remaining id is weekly", (a, b) => a == b, first(partial).id, "go-weekly")
})

test("parseGoUsage returns empty for non-object input or empty usage", () => {
  assertion(~message="Non-object input returns empty", (a, b) => a == b, parse(JSON.Null)->Array.length, 0)
  assertion(
    ~message="Empty usage returns empty",
    (a, b) => a == b,
    parse(usageJson([]))->Array.length,
    0,
  )
  assertion(
    ~message="Non-object usage returns empty",
    (a, b) => a == b,
    parse(JSON.Object(Dict.fromArray([("usage", JSON.String("invalid"))])))->Array.length,
    0,
  )
})

test("parseGoUsage ignores unknown fields in a window", () => {
  let result = parse(usageJson([("rolling", window([
    ("status", JSON.String("rate-limited")),
    ("percent", JSON.Number(88.0)),
    ("resetsAt", JSON.String("")),
    ("futureField", JSON.Object(Dict.fromArray([("anything", JSON.Boolean(true))]))),
  ]))]))
  assertion(~message="Unknown fields do not prevent parsing", (a, b) => a == b, result->Array.length, 1)
  assertion(~message="Percent is preserved", (a, b) => a == b, first(result).used, 88.0)
})

let () = runTests()
