// src/Providers/OpenAITests.res
// Tests for OpenAI provider: createOpenAIProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open OpenAI
open RescriptTest

autoBoot := false

// --- Tests --------------------------------------------------------------------

test("createOpenAIProvider returns provider with correct metadata", () => {
  let provider = createOpenAIProvider()
  assertion(~message="id is openai", (a, b) => a == b, provider.id, "openai")
  assertion(~message="displayName is OpenAI", (a, b) => a == b, provider.displayName, "OpenAI")
  assertion(~message="category is subscription", (a, b) => a == b, provider.category, "subscription")
  assertion(~message="authStrategy is oauth", (a, b) => a == b, provider.authStrategy, #oauth)
})

// Run all tests
let () = runTests()
