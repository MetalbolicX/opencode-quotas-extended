// src/Providers/GeminiTests.res
// Tests for Gemini provider: createGeminiProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is deferred to PR 6-5 wiring.

open Gemini
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createGeminiProvider returns provider with correct metadata", () => {
  let provider = createGeminiProvider()
  assertion(~message="id is gemini", (a, b) => a == b, provider.id, "gemini")
  assertion(~message="displayName is Google Gemini", (a, b) => a == b, provider.displayName, "Google Gemini")
  assertion(~message="category is api-spend", (a, b) => a == b, provider.category, "api-spend")
  assertion(~message="authStrategy is env", (a, b) => a == b, provider.authStrategy, #env)
})

// Run all tests
let () = runTests()
