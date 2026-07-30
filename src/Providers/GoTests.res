// src/Providers/GoTests.res
// Tests for Go provider: createGoProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open Go
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createGoProvider returns provider with correct metadata", () => {
  let provider = createGoProvider()
  assertion(~message="id is go", (a, b) => a == b, provider.id, "go")
  assertion(~message="displayName is opencode Go", (a, b) => a == b, provider.displayName, "opencode Go")
  assertion(~message="category is coding-plan", (a, b) => a == b, provider.category, "coding-plan")
  assertion(~message="authStrategy is api", (a, b) => a == b, provider.authStrategy, #api)
})

// Run all tests
let () = runTests()
