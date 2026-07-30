// src/Providers/ZenTests.res
// Tests for Zen provider: createZenProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open Zen
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createZenProvider returns provider with correct metadata", () => {
  let provider = createZenProvider()
  assertion(~message="id is zen", (a, b) => a == b, provider.id, "zen")
  assertion(~message="displayName is opencode Zen", (a, b) => a == b, provider.displayName, "opencode Zen")
  assertion(~message="category is coding-plan", (a, b) => a == b, provider.category, "coding-plan")
  assertion(~message="authStrategy is api", (a, b) => a == b, provider.authStrategy, #api)
})

// Run all tests
let () = runTests()
