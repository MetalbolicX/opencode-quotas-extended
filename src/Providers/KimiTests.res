// src/Providers/KimiTests.res
// Tests for Kimi provider: createKimiProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open Kimi
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createKimiProvider returns provider with correct metadata", () => {
  let provider = createKimiProvider()
  assertion(~message="id is kimi", (a, b) => a == b, provider.id, "kimi")
  assertion(~message="displayName is Kimi / Moonshot", (a, b) => a == b, provider.displayName, "Kimi / Moonshot")
  assertion(~message="category is coding-plan", (a, b) => a == b, provider.category, "coding-plan")
  assertion(~message="authStrategy is oauth", (a, b) => a == b, provider.authStrategy, #oauth)
})

// Run all tests
let () = runTests()
