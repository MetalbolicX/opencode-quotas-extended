// src/Providers/CodingPlanParseTests.res
// Tests for CodingPlanParse module: parseUsage, parseZaiLimits, parseMonitorLimits, windowMap.

open CodingPlanParse
open RescriptTest

autoBoot := false

// Helper to safely get first element (throws if empty, for tests only)
let first = (arr: array<'a>): 'a => Belt.Array.getExn(arr, 0)

// --- Helper builders ------------------------------------------------------------

type windowEntry = {
  label: string,
  used: float,
  limit: option<float>,
}

let makeWindowsJson = (windows: array<windowEntry>): JSON.t => {
  let windowsArr = windows->Array.map(w => {
    let limitPair: option<(string, JSON.t)> = switch w.limit {
    | Some(l) => Some(("limit", JSON.Number(l)))
    | None => None
    }
    let pairs: array<(string, JSON.t)> = switch limitPair {
    | Some(p) => [("label", JSON.String(w.label)), ("used", JSON.Number(w.used)), p]
    | None => [("label", JSON.String(w.label)), ("used", JSON.Number(w.used))]
    }
    JSON.Object(Dict.fromArray(pairs))
  })
  JSON.Object(Dict.fromArray([("windows", JSON.Array(windowsArr))]))
}

// --- parseUsage tests ------------------------------------------------------------

test("parseUsage handles valid windows array", () => {
  let json = makeWindowsJson([
    { label: "24h", used: 45.0, limit: Some(100.0) },
    { label: "30d", used: 20.0, limit: Some(100.0) },
  ])
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should return 2 entries",
    (a, b) => a == b,
    result->Array.length,
    2,
  )
    let firstEntry = first(result)
    assertion(~message="First entry has correct id", (a, b) => a == b, firstEntry.id, "zen-24h")
    assertion(~message="First entry has correct window", (a, b) => a == b, firstEntry.window, #daily)
})

test("parseUsage handles empty windows array", () => {
  let json = makeWindowsJson([])
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should return empty array",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseUsage handles credits with balance", () => {
  let json = JSON.Object(Dict.fromArray([
    ("windows", JSON.Array([])),
    ("credits", JSON.Object(Dict.fromArray([
      ("balance", JSON.Number(500.0)),
      // Note: unlimited field absent means it's not unlimited
    ]))),
  ]))
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should have credits entry",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  assertion(
    ~message="Credits entry has correct unit",
    (a, b) => a == b,
    first(result).unit,
    "credits",
  )
})

test("parseUsage handles unlimited credits", () => {
  // Note: unlimited field present with any value means unlimited
  // (implementation treats any non-null as truthy)
  let json = JSON.Object(Dict.fromArray([
    ("windows", JSON.Array([])),
    ("credits", JSON.Object(Dict.fromArray([
      ("unlimited", JSON.Number(1.0)),  // any non-null value triggers unlimited
    ]))),
  ]))
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should return empty when unlimited",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseUsage handles malformed JSON (non-object)", () => {
  let result = parseUsage(~json=JSON.Null, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should return empty array for null",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseUsage skips entries with no used value", () => {
  let json = JSON.Object(Dict.fromArray([
    ("windows", JSON.Array([
      JSON.Object(Dict.fromArray([
        ("label", JSON.String("24h")),
        ("limit", JSON.Number(100.0)),
      ]))
    ])),
  ]))
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should skip entry without used",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseUsage handles numeric string used value", () => {
  let json = JSON.Object(Dict.fromArray([
    ("windows", JSON.Array([
      JSON.Object(Dict.fromArray([
        ("label", JSON.String("24h")),
        ("used", JSON.String("45.5")),
        ("limit", JSON.Number(100.0)),
      ]))
    ])),
  ]))
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should parse string number as used",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  assertion(
    ~message="Used value should be 45.5",
    (a, b) => a == b,
    first(result).used,
    45.5,
  )
})

test("parseUsage handles percentage in used field", () => {
  let json = JSON.Object(Dict.fromArray([
    ("windows", JSON.Array([
      JSON.Object(Dict.fromArray([
        ("label", JSON.String("24h")),
        ("used", JSON.String("75%")),
        ("limit", JSON.Number(100.0)),
      ]))
    ])),
  ]))
  let result = parseUsage(~json, ~idPrefix="zen", ~providerName="Zen")
  assertion(
    ~message="Should strip trailing %",
    (a, b) => a == b,
    first(result).used,
    75.0,
  )
})

// --- windowMap tests -------------------------------------------------------------

test("windowMap maps 24h to daily", () => {
  let result = windowMap(Some("24h"))
  assertion(
    ~message="24h should map to daily",
    (a, b) => a == b,
    result,
    #daily,
  )
})

test("windowMap maps 30d to monthly", () => {
  let result = windowMap(Some("30d"))
  assertion(
    ~message="30d should map to monthly",
    (a, b) => a == b,
    result,
    #monthly,
  )
})

test("windowMap maps 5h to rolling-5h", () => {
  let result = windowMap(Some("5h"))
  assertion(
    ~message="5h should map to rolling-5h",
    (a, b) => a == b,
    result,
    #\"rolling-5h",
  )
})

test("windowMap maps unknown to rolling", () => {
  let result = windowMap(Some("unknown"))
  assertion(
    ~message="Unknown should map to rolling",
    (a, b) => a == b,
    result,
    #rolling,
  )
})

test("windowMap maps None to rolling", () => {
  let result = windowMap(None)
  assertion(
    ~message="None should map to rolling",
    (a, b) => a == b,
    result,
    #rolling,
  )
})

test("windowMap maps 1m to rolling-mcp", () => {
  let result = windowMap(Some("1m"))
  assertion(
    ~message="1m should map to rolling-mcp",
    (a, b) => a == b,
    result,
    #\"rolling-mcp",
  )
})

// --- parseMonitorLimits tests ----------------------------------------------------

test("parseMonitorLimits is alias for parseUsage", () => {
  let json = makeWindowsJson([
    { label: "24h", used: 50.0, limit: Some(100.0) },
  ])
  let result = parseMonitorLimits(~json, ~idPrefix="kimi", ~providerName="Kimi")
  assertion(
    ~message="parseMonitorLimits should return same result as parseUsage",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
})

// --- zaiWindow tests -------------------------------------------------------------

test("zaiWindow full plan TIME_LIMIT 5h", () => {
  let result = zaiWindow("TIME_LIMIT", Some(5.0), false)
  assertion(
    ~message="Full plan TIME_LIMIT 5h -> rolling-5h",
    (a, b) => a == b,
    result,
    #\"rolling-5h",
  )
})

test("zaiWindow full plan MCP_LIMIT", () => {
  let result = zaiWindow("MCP_LIMIT", None, false)
  assertion(
    ~message="Full plan MCP_LIMIT -> rolling-mcp",
    (a, b) => a == b,
    result,
    #\"rolling-mcp",
  )
})

test("zaiWindow full plan TOKENS_LIMIT", () => {
  let result = zaiWindow("TOKENS_LIMIT", None, false)
  assertion(
    ~message="Full plan TOKENS_LIMIT -> rolling-tokens",
    (a, b) => a == b,
    result,
    #\"rolling-tokens",
  )
})

test("zaiWindow lite plan TIME_LIMIT 5h becomes rolling-mcp", () => {
  let result = zaiWindow("TIME_LIMIT", Some(5.0), true)
  assertion(
    ~message="Lite plan TIME_LIMIT 5h -> rolling-mcp",
    (a, b) => a == b,
    result,
    #\"rolling-mcp",
  )
})

test("zaiWindow lite plan TOKENS_LIMIT 3 becomes rolling-5h", () => {
  let result = zaiWindow("TOKENS_LIMIT", Some(3.0), true)
  assertion(
    ~message="Lite plan TOKENS_LIMIT 3 -> rolling-5h",
    (a, b) => a == b,
    result,
    #\"rolling-5h",
  )
})

test("zaiWindow lite plan TOKENS_LIMIT 6 becomes rolling-weekly", () => {
  let result = zaiWindow("TOKENS_LIMIT", Some(6.0), true)
  assertion(
    ~message="Lite plan TOKENS_LIMIT 6 -> rolling-weekly",
    (a, b) => a == b,
    result,
    #\"rolling-weekly",
  )
})

test("zaiWindow full plan TIME_LIMIT >= 168 becomes rolling-weekly", () => {
  let result = zaiWindow("TIME_LIMIT", Some(200.0), false)
  assertion(
    ~message="Full plan TIME_LIMIT 200 -> rolling-weekly",
    (a, b) => a == b,
    result,
    #\"rolling-weekly",
  )
})

// --- windowRank tests ------------------------------------------------------------

test("windowRank daily is 0", () => {
  let result = windowRank(#daily)
  assertion(~message="daily rank", (a, b) => a == b, result, 0)
})

test("windowRank monthly is 1", () => {
  let result = windowRank(#monthly)
  assertion(~message="monthly rank", (a, b) => a == b, result, 1)
})

test("windowRank rolling-5h is 2", () => {
  let result = windowRank(#\"rolling-5h")
  assertion(~message="rolling-5h rank", (a, b) => a == b, result, 2)
})

test("windowRank rolling is 7 (lowest priority)", () => {
  let result = windowRank(#rolling)
  assertion(~message="rolling rank", (a, b) => a == b, result, 7)
})

// --- parseZaiLimits tests --------------------------------------------------------

test("parseZaiLimits handles valid limits array", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("kind", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(5.0)),
          ("label", JSON.String("5h")),
          ("used", JSON.Number(50.0)),
          ("percentage", JSON.Number(50.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ]))
      ])),
      ("level", JSON.String("standard")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai", ~isLitePlan=false)
  assertion(
    ~message="Should return 1 entry",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  assertion(
    ~message="Should have rolling-5h window",
    (a, b) => a == b,
    first(result).window,
    #\"rolling-5h",
  )
})

test("parseZaiLimits handles empty limits", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai", ~isLitePlan=false)
  assertion(
    ~message="Should return empty array",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseZaiLimits handles malformed JSON", () => {
  let result = parseZaiLimits(~json=JSON.Null, ~idPrefix="zai", ~providerName="z.ai", ~isLitePlan=false)
  assertion(
    ~message="Should return empty for null",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseZaiLimits detects lite plan", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("kind", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(5.0)),
          ("label", JSON.String("5h")),
          ("used", JSON.Number(50.0)),
          ("percentage", JSON.Number(50.0)),
        ]))
      ])),
      ("level", JSON.String("lite")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai", ~isLitePlan=true)
  assertion(
    ~message="Lite plan TIME_LIMIT 5h should be rolling-mcp",
    (a, b) => a == b,
    first(result).window,
    #\"rolling-mcp",
  )
})

// Run all tests
let () = runTests()
