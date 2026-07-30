// src/Providers/AnthropicTests.res
// Tests for Anthropic provider: createAnthropicProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is deferred to PR 6-5 wiring.

open Anthropic
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createAnthropicProvider returns provider with correct metadata", () => {
  let provider = createAnthropicProvider()
  assertion(~message="id is anthropic", (a, b) => a == b, provider.id, "anthropic")
  assertion(~message="displayName is Anthropic", (a, b) => a == b, provider.displayName, "Anthropic")
  assertion(~message="category is api-spend", (a, b) => a == b, provider.category, "api-spend")
  assertion(~message="authStrategy is env", (a, b) => a == b, provider.authStrategy, #env)
})

// Run all tests
let () = runTests()
