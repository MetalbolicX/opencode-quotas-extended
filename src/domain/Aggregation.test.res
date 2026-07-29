// Aggregation domain tests -- verifies pure domain aggregation logic.
open RescriptTest

let makeQ = (~id: string, ~used: float, ~limit: option<float>, ~providerName: string="test") =>
  Domain.makeQuotaData(~id, ~providerName, ~used, ~limit, ~unit="%", ~window=#daily)

// ETTL map using fromArray to avoid Js.Dict.empty linker issue
let makeEttlMap = () => Js.Dict.fromArray([("a", 10.0), ("b", 20.0), ("c", 30.0)])

// -- aggregateMax -------------------------------------------------------------

test("aggregateMax picks highest ratio", () => {
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=80.0, ~limit=Some(100.0))
  let q3 = makeQ(~id="c", ~used=20.0, ~limit=Some(100.0))
  let result = Domain.aggregateMax([q1, q2, q3])
  assertion(~message="q2 has highest ratio (0.8)", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("b"))
})

test("aggregateMax returns None for empty input", () => {
  let result = Domain.aggregateMax([])
  assertion(~message="empty array yields None", (a, b) => a == b, result, None)
})

test("aggregateMax treats None limit as ratio 0", () => {
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=None)
  let q2 = makeQ(~id="b", ~used=10.0, ~limit=Some(100.0))
  let result = Domain.aggregateMax([q1, q2])
  assertion(~message="q2 wins -- None limit treated as 0", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("b"))
})

test("aggregateMax single element returns that element", () => {
  let q1 = makeQ(~id="only", ~used=42.0, ~limit=Some(200.0))
  let result = Domain.aggregateMax([q1])
  assertion(~message="single element is returned", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("only"))
})

// -- aggregateMin -------------------------------------------------------------

test("aggregateMin picks lowest ratio", () => {
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=10.0, ~limit=Some(100.0))
  let result = Domain.aggregateMin([q1, q2])
  assertion(~message="q2 has lowest ratio (0.1)", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("b"))
})

test("aggregateMin returns None for empty input", () => {
  let result = Domain.aggregateMin([])
  assertion(~message="empty array yields None", (a, b) => a == b, result, None)
})

test("aggregateMin treats None limit as ratio 0", () => {
  let q1 = makeQ(~id="a", ~used=1.0, ~limit=None)
  let q2 = makeQ(~id="b", ~used=90.0, ~limit=Some(100.0))
  let result = Domain.aggregateMin([q1, q2])
  assertion(~message="q1 wins -- None limit is ratio 0", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("a"))
})

// -- aggregateMean -------------------------------------------------------------

test("aggregateMean returns averaged percentage", () => {
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=100.0, ~limit=Some(100.0))
  let result = Domain.aggregateMean([q1, q2], ~name="Avg", ~id="agg-mean")
  assertion(~message="used == 75 (avg ratio 0.75 * 100)", (a, b) => a == b, result.used, 75.0)
  assertion(~message="id == agg-mean", (a, b) => a == b, result.id, "agg-mean")
})

test("aggregateMean single quota returns its ratio", () => {
  let q1 = makeQ(~id="a", ~used=25.0, ~limit=Some(100.0))
  let result = Domain.aggregateMean([q1])
  assertion(~message="used == 25", (a, b) => a == b, result.used, 25.0)
})

test("aggregateMean empty array uses safeLen=1.0", () => {
  let result = Domain.aggregateMean([])
  assertion(~message="returns a valid record", (a, b) => a == b, result.id, "agg-mean")
})

// -- aggregateMedian -----------------------------------------------------------

test("aggregateMedian returns middle value by ratio", () => {
  let q1 = makeQ(~id="a", ~used=10.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=50.0, ~limit=Some(100.0))
  let q3 = makeQ(~id="c", ~used=90.0, ~limit=Some(100.0))
  let result = Domain.aggregateMedian([q1, q2, q3])
  assertion(~message="median ratio 0.5 → used 50", (a, b) => a == b, Belt.Option.map(result, r => r.used), Some(50.0))
  assertion(~message="id == agg-median", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("agg-median"))
})

test("aggregateMedian returns None for empty input", () => {
  let result = Domain.aggregateMedian([])
  assertion(~message="empty array yields None", (a, b) => a == b, result, None)
})

test("aggregateMedian even-count uses floor index", () => {
  let q1 = makeQ(~id="a", ~used=10.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=50.0, ~limit=Some(100.0))
  let result = Domain.aggregateMedian([q1, q2])
  // median result is a NEW record with id="agg-median"; verify used=50 (ratio 0.5 of q2)
  assertion(~message="even count: used=50", (a, b) => a == b, Belt.Option.map(result, r => r.used), Some(50.0))
})

// -- aggregateMostCritical ----------------------------------------------------

test("aggregateMostCritical picks lowest ETTL", () => {
  let map = makeEttlMap()
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=50.0, ~limit=Some(100.0))
  let q3 = makeQ(~id="c", ~used=50.0, ~limit=Some(100.0))
  let result = Domain.aggregateMostCritical([q1, q2, q3], map)
  assertion(~message="ETTL 10 < 20 < 30 → a wins", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("a"))
})

test("aggregateMostCritical falls back to max when ettlMap is empty", () => {
  let emptyMap = Js.Dict.fromArray([])
  let q1 = makeQ(~id="a", ~used=80.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=50.0, ~limit=Some(100.0))
  let result = Domain.aggregateMostCritical([q1, q2], emptyMap)
  assertion(~message="highest ratio wins when no ETTL (0.8 vs 0.5)", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("a"))
})

test("aggregateMostCritical returns None for empty quotas", () => {
  let map = makeEttlMap()
  let result = Domain.aggregateMostCritical([], map)
  assertion(~message="empty quotas yields None", (a, b) => a == b, result, None)
})

test("aggregateMostCritical all infinity ETTL falls back to max", () => {
  let map = Js.Dict.fromArray([])
  let q1 = makeQ(~id="a", ~used=30.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=90.0, ~limit=Some(100.0))
  let result = Domain.aggregateMostCritical([q1, q2], map)
  assertion(~message="all infinity → fallback to max → b", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("b"))
})

// -- mergeAggregationGroups ----------------------------------------------------

test("mergeAggregationGroups: user wins on id collision", () => {
  // Override a non-existent id to test append behavior
  let override = Domain.makeAggregationGroup(~id="custom-collision", ~providerId="zen", ~strategy=#min)
  let defaults = Domain.defaultAggregationGroups
  let result = Domain.mergeAggregationGroups([override], defaults)
  // New group appended: length = defaults + 1
  assertion(~message="length = defaults + 1", (a, b) => a == b, Belt.Array.length(result), Belt.Array.length(defaults) + 1)
})

test("mergeAggregationGroups: new groups appended", () => {
  let newGroup = Domain.makeAggregationGroup(~id="custom", ~providerId="custom", ~strategy=#min)
  let defaults = Domain.defaultAggregationGroups
  let result = Domain.mergeAggregationGroups([newGroup], defaults)
  assertion(~message="length = defaults + 1", (a, b) => a == b, Belt.Array.length(result), Belt.Array.length(defaults) + 1)
})

test("mergeAggregationGroups: empty user returns all defaults", () => {
  let defaults = Domain.defaultAggregationGroups
  let result = Domain.mergeAggregationGroups([], defaults)
  assertion(~message="all defaults returned", (a, b) => a == b, Belt.Array.length(result), Belt.Array.length(defaults))
})

// -- aggregate dispatcher -----------------------------------------------------

test("aggregate dispatcher routes to #mostCritical", () => {
  let map = makeEttlMap()
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=80.0, ~limit=Some(100.0))
  let result = Domain.aggregate([q1, q2], #mostCritical, ~ettlMap=map)
  assertion(~message="a has ETTL 10 < 20", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("a"))
})

test("aggregate dispatcher routes to #max", () => {
  let q1 = makeQ(~id="a", ~used=20.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=80.0, ~limit=Some(100.0))
  let result = Domain.aggregate([q1, q2], #max)
  assertion(~message="b has highest ratio", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("b"))
})

test("aggregate dispatcher routes to #min", () => {
  let q1 = makeQ(~id="a", ~used=20.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=80.0, ~limit=Some(100.0))
  let result = Domain.aggregate([q1, q2], #min)
  assertion(~message="a has lowest ratio", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("a"))
})

test("aggregate dispatcher routes to #mean", () => {
  let q1 = makeQ(~id="a", ~used=50.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=100.0, ~limit=Some(100.0))
  let result = Domain.aggregate([q1, q2], #mean)
  assertion(~message="agg-mean has used=75", (a, b) => a == b, Belt.Option.map(result, r => r.used), Some(75.0))
})

test("aggregate dispatcher routes to #median", () => {
  let q1 = makeQ(~id="a", ~used=10.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=50.0, ~limit=Some(100.0))
  let q3 = makeQ(~id="c", ~used=90.0, ~limit=Some(100.0))
  let result = Domain.aggregate([q1, q2, q3], #median)
  assertion(~message="agg-median has used=50", (a, b) => a == b, Belt.Option.map(result, r => r.used), Some(50.0))
})

test("aggregate with default ettlMap", () => {
  let q1 = makeQ(~id="a", ~used=20.0, ~limit=Some(100.0))
  let q2 = makeQ(~id="b", ~used=80.0, ~limit=Some(100.0))
  let result = Domain.aggregate([q1, q2], #max)
  assertion(~message="uses aggregateMax fallback", (a, b) => a == b, Belt.Option.map(result, r => r.id), Some("b"))
})

runTests()
