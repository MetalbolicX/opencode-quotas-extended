// src/Providers/MinimaxTests.res
// Tests for Minimax provider: createMinimaxProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// CLI parsing logic is covered by CodingPlanParseTests.

open Minimax
open RescriptTest

autoBoot := false

// --- Tests --------------------------------------------------------------------

test("createMinimaxProvider returns provider with correct metadata", () => {
  let provider = createMinimaxProvider()
  assertion(~message="id is minimax", (a, b) => a == b, provider.id, "minimax")
  assertion(~message="displayName is Minimax Coding Plan", (a, b) => a == b, provider.displayName, "Minimax Coding Plan")
  assertion(~message="category is subscription", (a, b) => a == b, provider.category, "subscription")
  assertion(~message="authStrategy is api", (a, b) => a == b, provider.authStrategy, #api)
})

// Run all tests
let () = runTests()
