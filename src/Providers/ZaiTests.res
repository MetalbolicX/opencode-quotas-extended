// src/Providers/ZaiTests.res
// Tests for Zai provider: createZaiProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open Zai
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createZaiProvider returns provider with correct metadata", () => {
  let provider = createZaiProvider()
  assertion(~message="id is zai", (a, b) => a == b, provider.id, "zai")
  assertion(~message="displayName is z.ai Coding Plan", (a, b) => a == b, provider.displayName, "z.ai Coding Plan")
  assertion(~message="category is coding-plan", (a, b) => a == b, provider.category, "coding-plan")
  assertion(~message="authStrategy is oauth", (a, b) => a == b, provider.authStrategy, #oauth)
})

// Run all tests
let () = runTests()
