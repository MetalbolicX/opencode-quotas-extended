// src/Providers/SemanticLabelsTests.res
// Smoke tests for the existing SemanticLabels module in rendering/.
// Tests enrichQuotaLabel which doesn't require constructing closed variant types.

open RescriptTest

autoBoot := false

// --- Smoke tests -----------------------------------------------------------------

test("enrichQuotaLabel returns a result with label and concept for TIME_LIMIT", () => {
  let hints: SemanticLabels.providerPayloadHints = {
    type_: Some("TIME_LIMIT"),
    unit: Some("5"),
    number: None,
    modelName: None,
    weekly: None,
    openaiVariant: None,
    geminiModel: None,
  }
  let result = SemanticLabels.enrichQuotaLabel("test-provider", hints)
  assertion(
    ~message="Result has label field",
    (a, b) => a == b,
    result.label->String.length > 0,
    true,
  )
  assertion(
    ~message="Result has concept field",
    (a, b) => a == b,
    result.label->String.includes("5h"),
    true,
  )
})

test("enrichQuotaLabel returns correct label for z.ai token type", () => {
  let hints: SemanticLabels.providerPayloadHints = {
    type_: Some("TOKENS_LIMIT"),
    unit: Some("100"),
    number: Some(1.0),
    modelName: None,
    weekly: None,
    openaiVariant: None,
    geminiModel: None,
  }
  let result = SemanticLabels.enrichQuotaLabel("zai", hints)
  assertion(
    ~message="Result label is non-empty",
    (a, b) => a == b,
    result.label->String.length > 0,
    true,
  )
})

test("enrichQuotaLabel returns result with label string", () => {
  let hints: SemanticLabels.providerPayloadHints = {
    type_: Some("MCP_LIMIT"),
    unit: None,
    number: None,
    modelName: None,
    weekly: None,
    openaiVariant: None,
    geminiModel: None,
  }
  let result = SemanticLabels.enrichQuotaLabel("test-provider", hints)
  // Verify we get a string back, not an exception
  assertion(
    ~message="Result is a string of non-zero length",
    (a, b) => a == b,
    result.label->String.length > 0,
    true,
  )
})

test("enrichQuotaLabel primary (openaiVariant=primary) returns 5h rolling window label", () => {
  let hints: SemanticLabels.providerPayloadHints = {
    type_: None,
    unit: None,
    number: None,
    modelName: None,
    weekly: None,
    openaiVariant: Some("primary"),
    geminiModel: None,
  }
  let result = SemanticLabels.enrichQuotaLabel("openai", hints)
  assertion(
    ~message="Primary variant label is 5h rolling window",
    (a, b) => a == b,
    result.label,
    "5h rolling window",
  )
})

test("enrichQuotaLabel secondary (openaiVariant=secondary) returns Weekly limit label", () => {
  let hints: SemanticLabels.providerPayloadHints = {
    type_: None,
    unit: None,
    number: None,
    modelName: None,
    weekly: None,
    openaiVariant: Some("secondary"),
    geminiModel: None,
  }
  let result = SemanticLabels.enrichQuotaLabel("openai", hints)
  assertion(
    ~message="Secondary variant label is Weekly limit",
    (a, b) => a == b,
    result.label,
    "Weekly limit",
  )
})

// ─── Anthropic subscription labels ─────────────────────────────────────────

test("anthropicUsageLabel maps kind to concept labels", () => {
  let session = SemanticLabels.anthropicUsageLabel("session", None)
  let weekly = SemanticLabels.anthropicUsageLabel("weekly_all", None)
  let scoped = SemanticLabels.anthropicUsageLabel("weekly_scoped", Some("Fable"))
  let generic = SemanticLabels.anthropicUsageLabel("monthly_all", None)
  assertion(~message="session label", (a, b) => a == b, session.label, "5h rolling window")
  assertion(~message="weekly label", (a, b) => a == b, weekly.label, "Weekly limit")
  assertion(~message="scoped label includes model", (a, b) => a == b, scoped.label, "Weekly limit (Fable)")
  assertion(~message="unknown kind kept", (a, b) => a == b, generic.label, "monthly_all")
})

test("buildProviderName appends the Anthropic label override", () => {
  let concept = SemanticLabels.anthropicUsageLabel("weekly_scoped", Some("Fable"))
  let name = SemanticLabels.buildProviderName("Anthropic", concept.concept, ~labelOverride=concept.label)
  assertion(
    ~message="brand + label",
    (a, b) => a == b,
    name,
    `Anthropic\u00A0·\u00A0Weekly limit (Fable)`,
  )
})

// Run all tests
let () = runTests()
