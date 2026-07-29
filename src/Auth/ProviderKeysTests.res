// src/Auth/ProviderKeysTests.res
// Tests for ProviderKeys module — covers spec scenarios P1 through P2.
open RescriptTest

autoBoot := false

// P1: known provider resolves to its mapped key
test("P1: known provider openai resolves to openai", () => {
  let result = ProviderKeys.authKey("openai")
  assertion(
    ~message=`Expected "openai", got "${result}"`,
    (a, b) => a == b,
    result,
    "openai",
  )
})

// P2: unknown provider falls back to the id itself
test("P2: unknown provider falls back to id itself", () => {
  let result = ProviderKeys.authKey("unknown-xyz")
  assertion(
    ~message=`Expected "unknown-xyz", got "${result}"`,
    (a, b) => a == b,
    result,
    "unknown-xyz",
  )
})

let () = runTests()
