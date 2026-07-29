// Prediction domain tests
// Tests only predictTimeToLimit which is the only function exported from Prediction module.
open RescriptTest
open Domain

let hp = (~timestamp: float, ~used: float, ~limit: float=100.0): historyPoint => {
  timestamp,
  used,
  limit: Some(limit),
}

test("predictTimeToLimit: empty history -> infinity", () => {
  let history: array<historyPoint> = []
  assertion(~message="empty -> infinity", (a, b) => a == b, predictTimeToLimit(history), infinity)
})

test("predictTimeToLimit: single point -> infinity", () => {
  let history = [hp(~timestamp=1000.0, ~used=50.0, ~limit=100.0)]
  assertion(~message="single -> infinity", (a, b) => a == b, predictTimeToLimit(history), infinity)
})

test("predictTimeToLimit: two points with same timestamp -> infinity (slope division by zero)", () => {
  // Both points at timestamp 1000.0 means slope = deltaUsed/deltaTime = 40/0 = infinity
  let history = [hp(~timestamp=1000.0, ~used=20.0, ~limit=100.0), hp(~timestamp=1000.0, ~used=60.0, ~limit=100.0)]
  let result = predictTimeToLimit(history)
  assertion(~message="same timestamp -> infinity", (a, b) => a == b, result, infinity)
})

test("predictTimeToLimit: positive slope but used > limit (should not go negative) -> infinity", () => {
  // used (100) is at limit, but function may still return infinity depending on implementation
  let history = [hp(~timestamp=1000.0, ~used=80.0, ~limit=100.0), hp(~timestamp=2000.0, ~used=100.0, ~limit=100.0)]
  let result = predictTimeToLimit(history)
  // When used >= limit, remaining <= 0, function may return 0 or infinity
  assertion(~message="at or over limit", (a, b) => a == b || a == infinity, result, infinity)
})

runTests()
