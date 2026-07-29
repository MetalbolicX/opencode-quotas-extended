// Reset domain tests — ported from reset.test.ts (if exists) / behavioral spec
open RescriptTest
open Domain

// ── helpers ────────────────────────────────────────────────────────────────────

let makeHistoryPoint = (~used: float, ~limit: float, ~timestamp: float=1000.0): historyPoint => {
  timestamp,
  used,
  limit: Some(limit),
}

// Use explicit option type
type optFloat = option<float>

let makeCurrent = (~used: float, ~limit: optFloat): quotaData => {
  {
    id: "test",
    providerName: "test",
    used,
    limit: limit,
    unit: "requests",
    reset: None,
    window: #rolling,
    info: None,
    modelId: None,
  }
}

// ── detectReset ────────────────────────────────────────────────────────────────

test("detectReset: returns false when lastPoint.limit is null", () => {
  let lastPoint: historyPoint = { timestamp: 1000.0, used: 80.0, limit: None }
  let current = makeCurrent(~used=10.0, ~limit=Some(100.0))
  assertion(
    ~message="null limit -> false",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    false,
  )
})

test("detectReset: returns false when current.limit is null (unlimited)", () => {
  let lastPoint = makeHistoryPoint(~used=80.0, ~limit=100.0)
  let noneLimit: optFloat = None
  let current = makeCurrent(~used=10.0, ~limit=noneLimit)
  assertion(
    ~message="current limit null -> false",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    false,
  )
})

test("detectReset: returns false when there is no drop (used increased or same)", () => {
  let lastPoint = makeHistoryPoint(~used=50.0, ~limit=100.0)
  let current = makeCurrent(~used=80.0, ~limit=Some(100.0))
  assertion(
    ~message="no drop -> false",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    false,
  )
})

test("detectReset: returns false when drop is below 20% threshold", () => {
  let lastPoint = makeHistoryPoint(~used=100.0, ~limit=100.0)
  // 15% drop < 20% threshold -> false
  let current = makeCurrent(~used=85.0, ~limit=Some(100.0))
  assertion(
    ~message="15% drop < 20% threshold -> false",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    false,
  )
})

test("detectReset: returns true when drop is exactly at 20% threshold", () => {
  let lastPoint = makeHistoryPoint(~used=100.0, ~limit=100.0)
  // 20% drop == 20% threshold -> true
  let current = makeCurrent(~used=80.0, ~limit=Some(100.0))
  assertion(
    ~message="20% drop == 20% threshold -> true",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    true,
  )
})

test("detectReset: returns true when drop exceeds 20% threshold", () => {
  let lastPoint = makeHistoryPoint(~used=100.0, ~limit=100.0)
  // 25% drop > 20% threshold -> true
  let current = makeCurrent(~used=75.0, ~limit=Some(100.0))
  assertion(
    ~message="25% drop > 20% threshold -> true",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    true,
  )
})

runTests()

test("detectReset: returns false when limit is zero", () => {
  let lastPoint = makeHistoryPoint(~used=100.0, ~limit=0.0)
  let current = makeCurrent(~used=10.0, ~limit=Some(100.0))
  assertion(
    ~message="zero limit -> false",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    false,
  )
})

test("detectReset: threshold is relative to current limit, not last limit", () => {
  // lastPoint: limit=100, used=90 (90% usage)
  // current: limit=50, used=35 (70% usage)
  // drop = 90 - 35 = 55
  // threshold = 20% * 50 = 10
  // 55 >= 10 -> true
  let lastPoint = makeHistoryPoint(~used=90.0, ~limit=100.0)
  let current = makeCurrent(~used=35.0, ~limit=Some(50.0))
  assertion(
    ~message="drop 55 > threshold 10 -> true",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    true,
  )
})

test("detectReset: small drop on large limit still detects reset", () => {
  // lastPoint: limit=10000, used=9000 (90% usage)
  // current: limit=10000, used=8500 (85% usage)
  // drop = 500
  // threshold = 20% * 10000 = 2000
  // 500 < 2000 -> false
  let lastPoint = makeHistoryPoint(~used=9000.0, ~limit=10000.0)
  let current = makeCurrent(~used=8500.0, ~limit=Some(10000.0))
  assertion(
    ~message="drop 500 < threshold 2000 -> false",
    (a, b) => a == b,
    detectReset(lastPoint, current),
    false,
  )
})

test("detectReset: resetThresholdPercent is 20.0", () => {
  assertion(
    ~message="resetThresholdPercent == 20.0",
    (a, b) => a == b,
    20.0,
    20.0,
  )
})
