// src/Auth/ProviderKeysTests.res
// Tests for ProviderKeys module — covers spec scenarios P1 through P4.
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

// P3: zen removal drops the opencode auth-key mapping (falls back to id)
test("P3: zen auth key mapping is removed (falls back to id)", () => {
  let result = ProviderKeys.authKey("zen")
  assertion(
    ~message=`Expected "zen", got "${result}"`,
    (a, b) => a == b,
    result,
    "zen",
  )
})

// P4: zen removal drops the pi auth-key mapping entirely (None)
test("P4: piAuthKey(zen) is None after removal", () => {
  assertion(
    ~message="piAuthKey(zen) must be None",
    (a, b) => a == b,
    ProviderKeys.piAuthKey("zen"),
    None,
  )
})

// P5: go and its opencode-go aliases keep their mappings (unrelated to removal)
test("P5: go keeps its auth keys", () => {
  assertion(~message="authKey(go)", (a, b) => a == b, ProviderKeys.authKey("go"), "opencode-go")
  assertion(~message="piAuthKey(go)", (a, b) => a == b, ProviderKeys.piAuthKey("go"), Some("opencode-go"))
})

let () = runTests()
