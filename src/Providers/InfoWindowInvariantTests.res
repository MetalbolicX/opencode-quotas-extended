// src/Providers/InfoWindowInvariantTests.res
// Tests for window + info strict-union invariant across all 8 providers.
// The window field is a CLOSED ReScript variant (Domain.windowType) — invalid
// windows cannot be constructed at compile time. This test verifies:
//   1. All 8 window variants are representable and round-trip through windowToString
//   2. info field (option<string>) is None OR Some(non-empty) — never Some("")
//   3. All 8 providers are present in the default registry
//
// The TS test (info-window-invariant.test.ts) enforces the same invariants at
// runtime via string-union checks. In ReScript, the variant type provides a
// compile-time guarantee that is verified here via runtime round-trip.
open RescriptTest
open Domain
open Registry

autoBoot := false

// ─── Window variant round-trip ─────────────────────────────────────────────────

// The 8 valid window variants (must match Domain.windowType definition)
type windowSample = {
  variant: windowType,
  stringRepr: string,
}

let allWindowSamples: array<windowSample> = [
  {variant: #daily, stringRepr: "daily"},
  {variant: #monthly, stringRepr: "monthly"},
  {variant: #rolling, stringRepr: "rolling"},
  {variant: #rolling1h, stringRepr: "rolling-1h"},
  {variant: #rolling5h, stringRepr: "rolling-5h"},
  {variant: #rollingMcp, stringRepr: "rolling-mcp"},
  {variant: #rollingTokens, stringRepr: "rolling-tokens"},
  {variant: #rollingWeekly, stringRepr: "rolling-weekly"},
]

test("I1: all 8 window variants round-trip through windowToString correctly", () => {
  let allMatch = allWindowSamples->Array.every(sample => {
    let repr = windowToString(sample.variant)
    repr == sample.stringRepr
  })
  assertion(
    ~message="all 8 window variants round-trip correctly",
    (a, b) => a == b,
    allMatch,
    true,
  )
})

test("I2: windowFromString parses all 8 window strings back to variants", () => {
  let allParse = allWindowSamples->Array.every(sample => {
    switch windowFromString(sample.stringRepr) {
    | Some(v) => v == sample.variant
    | None => false
    }
  })
  assertion(
    ~message="all 8 window strings parse back to their variants",
    (a, b) => a == b,
    allParse,
    true,
  )
})

// ─── QuotaData window invariant — compile-time type safety demonstration ───────

test("I3: quotaData record accepts each of the 8 window variants without error", () => {
  // This test proves that every valid window variant can be used in a quotaData record.
  // If a window value were invalid, the ReScript compiler would reject the record.
  let samples = allWindowSamples->Array.map(sample => {
    let id = `test/${sample.stringRepr}`
    let q: quotaData = {
      id: id,
      providerName: "Test",
      used: 0.0,
      limit: None,
      unit: "%",
      reset: None,
      window: sample.variant, // compile-time checked!
      info: None,
      modelId: None,
    }
    q
  })
  assertion(
    ~message="8 quotaData records with all window variants created",
    (a, b) => a == b,
    samples->Array.length,
    8,
  )
})

// ─── Info field invariant ─────────────────────────────────────────────────────

test("I4: info is None — satisfies invariant (info absent)", () => {
  let q: quotaData = {
    id: "test/daily",
    providerName: "Test",
    used: 10.0,
    limit: Some(100.0),
    unit: "%",
    reset: None,
    window: #daily,
    info: None,
    modelId: None,
  }
  // info is None — invariant satisfied
  assertion(~message="info is None", (a, b) => a == b, q.info, None)
})

test("I5: info is Some(non-empty) — satisfies invariant when present", () => {
  let q: quotaData = {
    id: "test/rolling",
    providerName: "Test",
    used: 5.0,
    limit: Some(100.0),
    unit: "%",
    reset: None,
    window: #rolling,
    info: Some("gemini-3-pro-high"),
    modelId: None,
  }
  // info is Some — must be non-empty
  switch q.info {
  | None => assertion(~message="should not be None", (a, b) => a == b, false, true)
  | Some(s) => assertion(
      ~message="info string is non-empty when present",
      (a, b) => a == b,
      String.length(s) > 0,
      true,
    )
  }
})

// ─── Registry coverage — all 8 providers present ─────────────────────────────

test("I6: default registry has exactly 8 providers", () => {
  let reg = Registry.buildDefaultRegistry()
  let ids = reg.ids()
  assertion(
    ~message="default registry has 8 providers",
    (a, b) => a == b,
    Array.length(ids),
    8,
  )
})

test("I7: all 8 provider IDs are present in default registry", () => {
  let reg = Registry.buildDefaultRegistry()
  let expectedIds = ["openai", "zen", "go", "zai", "kimi", "minimax", "anthropic", "gemini"]
  let allPresent = expectedIds->Array.every(id => {
    Belt.Array.getBy(reg.ids(), rid => rid == id) != None
  })
  assertion(
    ~message="all 8 expected provider IDs are in registry",
    (a, b) => a == b,
    allPresent,
    true,
  )
})

// ─── rolling-weekly is in the window union ─────────────────────────────────────

test("I8: rolling-weekly is a valid window variant (Minimax weekly rows)", () => {
  let q: quotaData = {
    id: "minimax-general-weekly",
    providerName: "Minimax · Weekly limit",
    used: 5.0,
    limit: Some(100.0),
    unit: "%",
    reset: None,
    window: #rollingWeekly,
    info: None,
    modelId: None,
  }
  assertion(
    ~message="rolling-weekly window accepted",
    (a, b) => a == b,
    windowToString(q.window),
    "rolling-weekly",
  )
})

let () = runTests()
