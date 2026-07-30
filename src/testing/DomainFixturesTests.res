// DomainFixtures tests — verifies test factory shapes.
// Phase 1: extracted from domain types (Types.res, Aggregation.res).
open RescriptTest
open Domain

// -- makeQuotaData -------------------------------------------------------------

test("makeQuotaData produces a valid quotaData record", () => {
  let q = DomainFixtures.makeQuotaData(
    ~id="test-id",
    ~providerName="test-provider",
    ~used=50.0,
    ~limit=Some(100.0),
  )
  assertion(~message="id is set", (a, b) => a == b, q.id, "test-id")
  assertion(~message="providerName is set", (a, b) => a == b, q.providerName, "test-provider")
  assertion(~message="used is set", (a, b) => a == b, q.used, 50.0)
  assertion(~message="limit is Some(100.0)", (a, b) => a == b, q.limit, Some(100.0))
  assertion(~message="unit defaults to requests", (a, b) => a == b, q.unit, "requests")
  assertion(~message="window defaults to #daily", (a, b) => a == b, q.window, #daily)
})

test("makeQuotaData defaults for optional fields", () => {
  let q = DomainFixtures.makeQuotaData(
    ~id="minimal",
    ~providerName="prov",
    ~used=0.0,
    ~limit=None,
  )
  assertion(~message="reset is None", (a, b) => a == b, q.reset, None)
  assertion(~message="info is None", (a, b) => a == b, q.info, None)
  assertion(~message="modelId is None", (a, b) => a == b, q.modelId, None)
})

// -- makeHistoryPoint ----------------------------------------------------------

test("makeHistoryPoint produces a valid historyPoint record", () => {
  let p = DomainFixtures.makeHistoryPoint(~timestamp=1000.0, ~used=42.0, ~limit=Some(200.0))
  assertion(~message="timestamp is set", (a, b) => a == b, p.timestamp, 1000.0)
  assertion(~message="used is set", (a, b) => a == b, p.used, 42.0)
  assertion(~message="limit is Some(200.0)", (a, b) => a == b, p.limit, Some(200.0))
})

test("makeHistoryPoint default limit is None", () => {
  let p = DomainFixtures.makeHistoryPoint(~timestamp=500.0, ~used=10.0)
  assertion(~message="limit defaults to None", (a, b) => a == b, p.limit, None)
})

// -- makeQuotaSnapshot ---------------------------------------------------------

test("makeQuotaSnapshot produces a valid quotaSnapshot record", () => {
  let q = DomainFixtures.makeQuotaData(
    ~id="snap-test",
    ~providerName="snap-provider",
    ~used=75.0,
    ~limit=Some(150.0),
  )
  let fetchedAt = Date.make(/* 2024-01-01 UTC */)
  let snap = DomainFixtures.makeQuotaSnapshot(~fetchedAt, ~data=[q])
  assertion(~message="fetchedAt is set", (a, b) => a == b, snap.fetchedAt, fetchedAt)
  assertion(~message="data has 1 element", (a, b) => a == b, snap.data->Belt.Array.length, 1)
  assertion(~message="errors defaults to None", (a, b) => a == b, snap.errors, None)
})

test("makeQuotaSnapshot can carry errors", () => {
  let fetchedAt = Date.make()
  let errors = Some(Dict.fromArray([("openai", "rate limited")]))
  let snap = DomainFixtures.makeQuotaSnapshot(~fetchedAt, ~data=[], ~errors)
  assertion(~message="errors is Some dict", (a, b) => a == b, snap.errors->Belt.Option.isSome, true)
})

// -- makeAggregationGroup ------------------------------------------------------

test("makeAggregationGroup produces a valid aggregationGroup record", () => {
  let g = DomainFixtures.makeAggregationGroup(
    ~id="test-group",
    ~providerId="test-provider",
    ~strategy=#max,
  )
  assertion(~message="id is set", (a, b) => a == b, g.id, "test-group")
  assertion(~message="providerId is set", (a, b) => a == b, g.providerId, "test-provider")
  assertion(~message="strategy is #max", (a, b) => a == b, g.strategy, #max)
})

test("makeAggregationGroup works with different strategies", () => {
  let strategies: array<aggregationStrategy> = [#mostCritical, #max, #min, #mean, #median]
  let rec checkAll = (i, failures) => {
    if i >= strategies->Belt.Array.length {
      failures
    } else {
      let s = strategies->Belt.Array.getExn(i)
      let g = DomainFixtures.makeAggregationGroup(~id="sg", ~providerId="p", ~strategy=s)
      if g.strategy == s {
        checkAll(i + 1, failures)
      } else {
        checkAll(i + 1, failures + 1)
      }
    }
  }
  assertion(
    ~message="all strategies round-trip correctly",
    (a, b) => a == b,
    checkAll(0, 0),
    0,
  )
})

runTests()
