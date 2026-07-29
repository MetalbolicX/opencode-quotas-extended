// Types domain tests -- minimal version to isolate linker crash
open RescriptTest

test("windowToString handles #daily", () => {
  let w = Domain.windowFromString("daily")->Belt.Option.getExn
  assertion(~message="daily", (a, b) => a == b, Domain.windowToString(w), "daily")
})

test("windowFromString returns Some for valid", () => {
  assertion(~message="daily parses", (a, b) => a == b, Domain.windowFromString("daily")->Belt.Option.isSome, true)
})

test("windowFromString returns None for invalid", () => {
  assertion(~message="invalid => None", (a, b) => a == b, Domain.windowFromString("invalid"), None)
})

test("strategyToString round-trips", () => {
  let s = Domain.strategyFromString("max")->Belt.Option.getExn
  assertion(~message="max round-trips", (a, b) => a == b, Domain.strategyFromString(Domain.strategyToString(s))->Belt.Option.isSome, true)
})

runTests()
