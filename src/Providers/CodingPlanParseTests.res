// src/Providers/CodingPlanParseTests.res
// Tests for CodingPlanParse module: parseUsage, parseZaiLimits, parseMonitorLimits, parseKimiUsages, windowMap.

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
    #rolling5h,
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
    #rollingMcp,
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
    #rolling5h,
  )
})

test("zaiWindow full plan MCP_LIMIT", () => {
  let result = zaiWindow("MCP_LIMIT", None, false)
  assertion(
    ~message="Full plan MCP_LIMIT -> rolling-mcp",
    (a, b) => a == b,
    result,
    #rollingMcp,
  )
})

test("zaiWindow full plan TOKENS_LIMIT", () => {
  let result = zaiWindow("TOKENS_LIMIT", None, false)
  assertion(
    ~message="Full plan TOKENS_LIMIT -> rolling-tokens",
    (a, b) => a == b,
    result,
    #rollingTokens,
  )
})

test("zaiWindow lite plan TIME_LIMIT 5h becomes rolling-mcp", () => {
  let result = zaiWindow("TIME_LIMIT", Some(5.0), true)
  assertion(
    ~message="Lite plan TIME_LIMIT 5h -> rolling-mcp",
    (a, b) => a == b,
    result,
    #rollingMcp,
  )
})

test("zaiWindow lite plan TOKENS_LIMIT 3 becomes rolling-5h", () => {
  let result = zaiWindow("TOKENS_LIMIT", Some(3.0), true)
  assertion(
    ~message="Lite plan TOKENS_LIMIT 3 -> rolling-5h",
    (a, b) => a == b,
    result,
    #rolling5h,
  )
})

test("zaiWindow lite plan TOKENS_LIMIT 6 becomes rolling-weekly", () => {
  let result = zaiWindow("TOKENS_LIMIT", Some(6.0), true)
  assertion(
    ~message="Lite plan TOKENS_LIMIT 6 -> rolling-weekly",
    (a, b) => a == b,
    result,
    #rollingWeekly,
  )
})

test("zaiWindow full plan TIME_LIMIT >= 168 becomes rolling-weekly", () => {
  let result = zaiWindow("TIME_LIMIT", Some(200.0), false)
  assertion(
    ~message="Full plan TIME_LIMIT 200 -> rolling-weekly",
    (a, b) => a == b,
    result,
    #rollingWeekly,
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
  let result = windowRank(#rolling5h)
  assertion(~message="rolling-5h rank", (a, b) => a == b, result, 2)
})

test("windowRank rolling is 7 (lowest priority)", () => {
  let result = windowRank(#rolling)
  assertion(~message="rolling rank", (a, b) => a == b, result, 7)
})

// --- parseZaiLimits tests --------------------------------------------------------

test("parseZaiLimits handles valid limits array", () => {
  // New schema: data.limits entries with type/percentage/currentValue/usage/number/nextResetTime
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(5.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(50.0)),
          ("remaining", JSON.Number(50.0)),
          ("percentage", JSON.Number(50.0)),
          ("nextResetTime", JSON.Number(1751328000000.0)),
        ]))
      ])),
      ("level", JSON.String("standard")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
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
    #rolling5h,
  )
  assertion(
    ~message="limit should be Some(100.0)",
    (a, b) => a == b,
    first(result).limit,
    Some(100.0),
  )
  assertion(
    ~message="reset should be Some ISO string",
    (a, b) => a == b,
    first(result).reset->Option.isSome,
    true,
  )
  // Regression: z.ai API returns nextResetTime in ms (13 digits like 1785809056980).
  // The legacy TS treated it as ms directly via `new Date(resetMs)`. The ReScript
  // port was dividing by 1000, which (combined with JS Date storing only integer ms)
  // collapsed real future dates to 1970 — making the reset column show "now".
  assertion(
    ~message="reset ms should equal the raw nextResetTime value (no /1000 conversion)",
    (a, b) => a == b,
    switch first(result).reset {
    | Some(d) => Date.getTime(d)
    | None => -1.0
    },
    1751328000000.0,
  )
})

test("parseZaiLimits handles empty limits", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Should return empty array",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseZaiLimits handles malformed JSON", () => {
  let result = parseZaiLimits(~json=JSON.Null, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Should return empty for null",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

test("parseZaiLimits lite plan TIME_LIMIT unit 5 becomes rolling-mcp with MCP quota label", () => {
  // Lite plan: TIME_LIMIT unit:5 → rolling-mcp / label "MCP quota"
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(5.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(50.0)),
          ("remaining", JSON.Number(50.0)),
          ("percentage", JSON.Number(50.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ]))
      ])),
      ("level", JSON.String("lite")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Should return 1 entry",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  assertion(
    ~message="Lite plan TIME_LIMIT 5h should be rolling-mcp",
    (a, b) => a == b,
    first(result).window,
    #rollingMcp,
  )
  assertion(
    ~message="Info label should be MCP quota",
    (a, b) => a == b,
    first(result).info,
    Some("MCP quota"),
  )
})

test("parseZaiLimits lite plan TOKENS_LIMIT unit 3 becomes rolling-5h", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TOKENS_LIMIT")),
          ("unit", JSON.Number(3.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(30.0)),
          ("remaining", JSON.Number(70.0)),
          ("percentage", JSON.Number(30.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ]))
      ])),
      ("level", JSON.String("lite")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Should return 1 entry",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  assertion(
    ~message="Lite plan TOKENS_LIMIT unit 3 should be rolling-5h",
    (a, b) => a == b,
    first(result).window,
    #rolling5h,
  )
  assertion(
    ~message="Info label should be 5h rolling window",
    (a, b) => a == b,
    first(result).info,
    Some("5h rolling window"),
  )
})

test("parseZaiLimits lite plan TOKENS_LIMIT unit 6 becomes rolling-weekly", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TOKENS_LIMIT")),
          ("unit", JSON.Number(6.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(80.0)),
          ("remaining", JSON.Number(20.0)),
          ("percentage", JSON.Number(80.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ]))
      ])),
      ("level", JSON.String("lite")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Lite plan TOKENS_LIMIT unit 6 should be rolling-weekly",
    (a, b) => a == b,
    first(result).window,
    #rollingWeekly,
  )
  assertion(
    ~message="Info label should be Weekly quota",
    (a, b) => a == b,
    first(result).info,
    Some("Weekly quota"),
  )
})

test("parseZaiLimits derives usage from currentValue/usage when percentage is absent", () => {
  // When percentage is absent/null, derive from currentValue/usage
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("MCP_LIMIT")),
          ("unit", JSON.Null),
          ("number", JSON.Null),
          ("usage", JSON.Number(200.0)),
          ("currentValue", JSON.Number(50.0)),
          ("remaining", JSON.Number(150.0)),
          ("percentage", JSON.Null),
          ("nextResetTime", JSON.Number(0.0)),
        ]))
      ])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Should return 1 entry",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  // currentValue=50, usage=200 → (50/200)*100 = 25%
  assertion(
    ~message="Used should be 25.0 (derived from currentValue/usage)",
    (a, b) => a == b,
    first(result).used,
    25.0,
  )
  assertion(
    ~message="limit should be Some(100.0)",
    (a, b) => a == b,
    first(result).limit,
    Some(100.0),
  )
})

test("parseZaiLimits full plan TIME_LIMIT unit 168 becomes rolling-weekly", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(168.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(100.0)),
          ("remaining", JSON.Number(0.0)),
          ("percentage", JSON.Number(100.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ]))
      ])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Full plan TIME_LIMIT unit 168 should be rolling-weekly",
    (a, b) => a == b,
    first(result).window,
    #rollingWeekly,
  )
})

test("parseZaiLimits output is sorted: rolling-mcp, rolling-5h, rolling-weekly", () => {
  // Multiple entries should come out in stable sorted order
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(5.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(50.0)),
          ("remaining", JSON.Number(50.0)),
          ("percentage", JSON.Number(50.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ])),
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("MCP_LIMIT")),
          ("unit", JSON.Null),
          ("number", JSON.Null),
          ("usage", JSON.Number(60.0)),
          ("currentValue", JSON.Number(30.0)),
          ("remaining", JSON.Number(30.0)),
          ("percentage", JSON.Number(50.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ])),
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(200.0)),
          ("number", JSON.Null),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(100.0)),
          ("remaining", JSON.Number(0.0)),
          ("percentage", JSON.Number(100.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ])),
      ])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="Should return 3 entries",
    (a, b) => a == b,
    result->Array.length,
    3,
  )
  // Sorted: rolling-mcp (0) → rolling-5h (1) → rolling-weekly (2)
  assertion(
    ~message="First entry should be rolling-mcp",
    (a, b) => a == b,
    Belt.Array.getExn(result, 0).window,
    #rollingMcp,
  )
  assertion(
    ~message="Second entry should be rolling-5h",
    (a, b) => a == b,
    Belt.Array.getExn(result, 1).window,
    #rolling5h,
  )
  assertion(
    ~message="Third entry should be rolling-weekly",
    (a, b) => a == b,
    Belt.Array.getExn(result, 2).window,
    #rollingWeekly,
  )
})

// Regression: lite plan detection must come from data.level, not a caller flag.
// Guards against the bug where Zai.res hard-coded isLitePlan=false and
// lite-plan rows rendered as `Token quota #N` instead of MCP/5h/Weekly.
test("parseZaiLimits data.level pro yields full-plan labels for TOKENS_LIMIT", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TOKENS_LIMIT")),
          ("unit", JSON.Number(3.0)),
          ("number", JSON.Number(5.0)),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(1.0)),
          ("remaining", JSON.Number(99.0)),
          ("percentage", JSON.Number(1.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ])),
      ])),
      ("level", JSON.String("pro")),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="level=pro TOKENS_LIMIT unit 3 should keep full-plan token label",
    (a, b) => a == b,
    first(result).info,
    Some("Token quota #5"),
  )
  assertion(
    ~message="level=pro TOKENS_LIMIT unit 3 should map to rolling-tokens (not 5h)",
    (a, b) => a == b,
    first(result).window,
    #rollingTokens,
  )
})

test("parseZaiLimits missing level field defaults to full-plan labels", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("limits", JSON.Array([
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TOKENS_LIMIT")),
          ("unit", JSON.Number(3.0)),
          ("number", JSON.Number(5.0)),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(1.0)),
          ("remaining", JSON.Number(99.0)),
          ("percentage", JSON.Number(1.0)),
          ("nextResetTime", JSON.Number(0.0)),
        ])),
      ])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  assertion(
    ~message="missing level field should treat as full-plan token row",
    (a, b) => a == b,
    first(result).info,
    Some("Token quota #5"),
  )
})

// =============================================================================
// parseKimiUsages tests — tier 1 (T1.2, T1.5, T1.6-part1, T1.10)
// Ships: full parser; rolling-window fixture coverage lands in next commit.
// =============================================================================

// T1.2: summary-only payload → 1 row, id=kimi-weekly, window=#rollingWeekly
test("parseKimiUsages summary-only yields 1 row with kimi-weekly id and rollingWeekly window", () => {
  let json = JSON.Object(Dict.fromArray([
    ("usage", JSON.Object(Dict.fromArray([
      ("used", JSON.String("12.5")),
      ("limit", JSON.String("100.0")),
      ("resetTime", JSON.String("")),
    ]))),
  ]))
  let result = parseKimiUsages(~json, ~idPrefix="kimi", ~providerName="Kimi / Moonshot")
  assertion(
    ~message="Should return 1 row",
    (a, b) => a == b,
    result->Array.length,
    1,
  )
  let firstEntry = first(result)
  assertion(~message="id should be kimi-weekly", (a, b) => a == b, firstEntry.id, "kimi-weekly")
  assertion(~message="window should be rollingWeekly", (a, b) => a == b, firstEntry.window, #rollingWeekly)
  assertion(
    ~message="used should be parsed from decimal string",
    (a, b) => a == b,
    firstEntry.used,
    12.5,
  )
  assertion(
    ~message="limit should be Some(100.0)",
    (a, b) => a == b,
    firstEntry.limit,
    Some(100.0),
  )
})

// T1.5: malformed root → []
test("parseKimiUsages malformed root (non-object) returns empty array", () => {
  let result = parseKimiUsages(~json=JSON.Null, ~idPrefix="kimi", ~providerName="Kimi / Moonshot")
  assertion(
    ~message="Should return empty array for null",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
  let result2 = parseKimiUsages(~json=JSON.Array([]), ~idPrefix="kimi", ~providerName="Kimi / Moonshot")
  assertion(
    ~message="Should return empty array for array",
    (a, b) => a == b,
    result2->Array.length,
    0,
  )
})

// T1.6 part 1: non-object row in limits array → skipped
test("parseKimiUsages skips non-object rows in limits array", () => {
  let json = JSON.Object(Dict.fromArray([
    ("limits", JSON.Array([
      JSON.String("not an object"),
      JSON.Number(42.0),
      JSON.Null,
    ])),
  ]))
  let result = parseKimiUsages(~json, ~idPrefix="kimi", ~providerName="Kimi / Moonshot")
  assertion(
    ~message="Should return 0 rows",
    (a, b) => a == b,
    result->Array.length,
    0,
  )
})

// T1.10: boosterWallet present at root does not affect output
test("parseKimiUsages boosterWallet present at root does not affect output", () => {
  let json = JSON.Object(Dict.fromArray([
    ("usage", JSON.Object(Dict.fromArray([
      ("used", JSON.String("5.0")),
      ("limit", JSON.String("50.0")),
      ("resetTime", JSON.String("")),
    ]))),
    ("limits", JSON.Array([
      JSON.Object(Dict.fromArray([
        ("window", JSON.Object(Dict.fromArray([
          ("duration", JSON.Number(300.0)),
          ("timeUnit", JSON.String("TIME_UNIT_MINUTE")),
        ]))),
        ("detail", JSON.Object(Dict.fromArray([
          ("used", JSON.String("2.0")),
          ("resetTime", JSON.String("")),
        ]))),
      ])),
    ])),
    ("boosterWallet", JSON.Object(Dict.fromArray([
      ("balance", JSON.String("999.0")),
      ("type", JSON.String("Booster")),
    ]))),
  ]))
  let result = parseKimiUsages(~json, ~idPrefix="kimi", ~providerName="Kimi / Moonshot")
  assertion(
    ~message="Should return 2 rows (same as without boosterWallet)",
    (a, b) => a == b,
    result->Array.length,
    2,
  )
  assertion(~message="First id should be kimi-weekly", (a, b) => a == b, Belt.Array.getExn(result, 0).id, "kimi-weekly")
  assertion(~message="Second id should be kimi-5h", (a, b) => a == b, Belt.Array.getExn(result, 1).id, "kimi-5h")
})

// Run all tests
let () = runTests()
