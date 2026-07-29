// AggregationDefaults domain tests — ported from aggregation-defaults.test.ts
open RescriptTest
open Domain

test("defaultAggregationGroups: array has 5 entries", () => {
  assertion(
    ~message="length == 5",
    (a, b) => a == b,
    defaultAggregationGroups->Belt.Array.length,
    5,
  )
})

test("each group has id, providerId, and strategy fields", () => {
  let rec check = (i, failures) => {
    if i >= defaultAggregationGroups->Belt.Array.length {
      failures
    } else {
      let g = defaultAggregationGroups->Belt.Array.getExn(i)
      let failures = if String.length(g.id) > 0 { failures } else { failures + 1 }
      let failures = if String.length(g.providerId) > 0 { failures } else { failures + 1 }
      check(i + 1, failures)
    }
  }
  assertion(
    ~message="all groups have non-empty id and providerId",
    (a, b) => a == b,
    check(0, 0),
    0,
  )
})

test("each id is a non-empty string", () => {
  let rec check = (i, failures) => {
    if i >= defaultAggregationGroups->Belt.Array.length {
      failures
    } else {
      let g = defaultAggregationGroups->Belt.Array.getExn(i)
      if String.length(g.id) > 0 {
        check(i + 1, failures)
      } else {
        check(i + 1, failures + 1)
      }
    }
  }
  assertion(
    ~message="all ids are non-empty strings",
    (a, b) => a == b,
    check(0, 0),
    0,
  )
})

test("id is unique per default group (no duplicates)", () => {
  let ids = defaultAggregationGroups->Belt.Array.map(g => g.id)
  // Check for duplicates by comparing each id with all others
  let rec hasDuplicates = (i: int): bool => {
    if i >= ids->Belt.Array.length { false }
    else {
      let id = ids->Belt.Array.getExn(i)
      let rec foundEarlier = (j: int): bool => {
        if j >= i { false }
        else if ids->Belt.Array.getExn(j) == id { true }
        else { foundEarlier(j + 1) }
      }
      if foundEarlier(0) { true }
      else { hasDuplicates(i + 1) }
    }
  }
  assertion(
    ~message="no duplicate ids",
    (a, b) => a == b,
    hasDuplicates(0),
    false,
  )
})

test("all 5 providerIds are the coding-plan providers", () => {
  let providerIds = defaultAggregationGroups->Belt.Array.map(g => g.providerId)
  let expected = ["zen", "go", "zai", "kimi", "minimax"]
  let rec check = (i, failures) => {
    if i >= expected->Belt.Array.length {
      failures
    } else {
      let exp = expected->Belt.Array.getExn(i)
      if providerIds->Belt.Array.some(p => p == exp) {
        check(i + 1, failures)
      } else {
        check(i + 1, failures + 1)
      }
    }
  }
  assertion(
    ~message="all 5 expected providerIds are present",
    (a, b) => a == b,
    check(0, 0),
    0,
  )
})

test("every default uses max strategy", () => {
  let rec check = (i, failures) => {
    if i >= defaultAggregationGroups->Belt.Array.length {
      failures
    } else {
      let g = defaultAggregationGroups->Belt.Array.getExn(i)
      if g.strategy == #max {
        check(i + 1, failures)
      } else {
        check(i + 1, failures + 1)
      }
    }
  }
  assertion(
    ~message="all groups use #max strategy",
    (a, b) => a == b,
    check(0, 0),
    0,
  )
})

test("expected ids are present (specific ids match)", () => {
  let ids = defaultAggregationGroups->Belt.Array.map(g => g.id)
  let expected = ["opencode-go-monthly", "opencode-zen-monthly", "zai-coding-plan-weekly", "kimi-daily", "minimax-monthly"]
  // Check each expected id exists in ids
  let rec checkAll = (i, missing) => {
    if i >= expected->Belt.Array.length {
      missing
    } else {
      let exp = expected->Belt.Array.getExn(i)
      if ids->Belt.Array.some(id => id == exp) {
        checkAll(i + 1, missing)
      } else {
        checkAll(i + 1, missing + 1)
      }
    }
  }
  assertion(
    ~message="all expected ids are present",
    (a, b) => a == b,
    checkAll(0, 0),
    0,
  )
})

runTests()


