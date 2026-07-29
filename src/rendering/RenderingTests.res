// Rendering module tests — Colors, TextClip, SemanticLabels, StatusBar, Renderers.
open RescriptTest

autoBoot := false

// ─── Colors ─────────────────────────────────────────────────────────────────

test("colorMap has at least 10 entries", () => {
  let size = Dict.size(Rendering.colorMap)
  assertion(
    ~message=`Expected >= 10, got ${size->Int.toString}`,
    (a, b) => a >= b,
    size,
    10,
  )
})

test("validColorNames is non-empty", () => {
  let names = Rendering.validColorNames
  assertion(
    ~message=`Expected non-empty array, got length ${names->Array.length->Int.toString}`,
    (a, b) => a > b,
    names->Array.length,
    0,
  )
})

// ─── TextClip ────────────────────────────────────────────────────────────────

test("clip returns string of length 10 for 'hello' with width=10", () => {
  let result = TextClip.clip("hello", ~width=10)
  let len = String.length(result)
  assertion(
    ~message=`Expected length 10, got ${len->Int.toString}; value="${result}"`,
    (a, b) => a == b,
    len,
    10,
  )
})

test("clip truncates long string to width=10", () => {
  let result = TextClip.clip("hello world this is a long string", ~width=10)
  let len = String.length(result)
  assertion(
    ~message=`Expected length 10, got ${len->Int.toString}; value="${result}"`,
    (a, b) => a == b,
    len,
    10,
  )
})

// ─── SemanticLabels ──────────────────────────────────────────────────────────

test("getLabel returns non-empty string for known concept", () => {
  let result = SemanticLabels.getLabel("z.ai-5-hour-rolling")
  let len = String.length(result)
  assertion(
    ~message=`Expected non-empty string, got "${result}"`,
    (a, b) => a > b,
    len,
    0,
  )
})

test("getLabel returns empty string for unknown concept", () => {
  let result = SemanticLabels.getLabel("unknown-concept-xyz")
  assertion(
    ~message=`Expected empty string, got "${result}"`,
    (a, b) => a == b,
    result,
    "",
  )
})

// ─── StatusBar ──────────────────────────────────────────────────────────────

test("renderBar returns string of length 10 for ratio=0.5, width=10", () => {
  let opts: StatusBar.barOptions = {
    width: Some(10.0),
    filledChar: Some("█"),
    emptyChar: Some("."),
    colorName: None,
    framed: None,
    colorSplit: None,
  }
  let result = StatusBar.renderBar(0.5, ~opts=opts)
  let len = String.length(result)
  assertion(
    ~message=`Expected length 10, got ${len->Int.toString}; value="${result}"`,
    (a, b) => a == b,
    len,
    10,
  )
})

test("renderBar returns empty string for ratio=0 with width=10", () => {
  let opts: StatusBar.barOptions = {
    width: Some(10.0),
    filledChar: Some("█"),
    emptyChar: Some("."),
    colorName: None,
    framed: None,
    colorSplit: None,
  }
  let result = StatusBar.renderBar(0.0, ~opts=opts)
  let len = String.length(result)
  assertion(
    ~message=`Expected length 10 (all empty), got ${len->Int.toString}; value="${result}"`,
    (a, b) => a == b,
    len,
    10,
  )
})

// ─── Renderers ───────────────────────────────────────────────────────────────

// Minimal quotaData record for testing
let sampleQuota: Domain.quotaData = {
  id: "test-provider",
  providerName: "TestProvider",
  used: 50.0,
  limit: Some(100.0),
  unit: "req",
  reset: None,
  window: #daily,
  info: None,
  modelId: None,
}

let sampleQuotas: array<Domain.quotaData> = [sampleQuota]

let minimalCtx: Renderers.renderContext = {
  mode: #table,
  color: None,
  compact: Some(false),
  progressBar: Some({
    width: Some(10.0),
    filledChar: Some("█"),
    emptyChar: Some("."),
    color: Some(false),
    gradients: Some(false),
  }),
  terminalWidth: None,
  header: None,
  t: { t: (key, _vars) => key },
}

test("selectRenderer(#table) returns renderer whose render returns non-empty string", () => {
  let renderer = Renderers.selectRenderer(#table)
  let result = renderer.render(sampleQuotas, minimalCtx)
  let len = String.length(result)
  assertion(
    ~message=`Expected non-empty string, got "${result}"`,
    (a, b) => a > b,
    len,
    0,
  )
})

test("selectRenderer(#json) returns renderer whose render returns JSON-parseable output", () => {
  let renderer = Renderers.selectRenderer(#json)
  let result = renderer.render(sampleQuotas, minimalCtx)
  let parsed = try {
    Some(JSON.parseOrThrow(result))
  } catch {
  | _ => None
  }
  assertion(
    ~message=`Expected valid JSON, got "${result}"`,
    (a, _b) => a != None,
    parsed,
    None,
  )
})

test("selectRenderer(#markdown) returns renderer whose render returns non-empty markdown string", () => {
  let renderer = Renderers.selectRenderer(#markdown)
  let result = renderer.render(sampleQuotas, minimalCtx)
  let len = String.length(result)
  assertion(
    ~message=`Expected non-empty markdown, got "${result}"`,
    (a, b) => a > b,
    len,
    0,
  )
})

runTests()
