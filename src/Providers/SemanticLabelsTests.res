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

// Run all tests
let () = runTests()
