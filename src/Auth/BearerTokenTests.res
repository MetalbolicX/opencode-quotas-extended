// src/Auth/BearerTokenTests.res
// Tests for BearerToken.extract — covers Api/OAuth/Wellknown/Env variants.
open RescriptTest

autoBoot := false

// BT1: Api credential extracts Bearer token
test("BT1: Api key extracts to Bearer token", () => {
  let cred = Credential.Api({variant: "api", key: "sk-test123"})
  let result = BearerToken.extract(cred)
  assertion(
    ~message=`Expected "Bearer sk-test123", got "${result}"`,
    (a, b) => a == b,
    result,
    "Bearer sk-test123",
  )
})

// BT2: OAuth credential extracts Bearer token
test("BT2: OAuth access token extracts to Bearer token", () => {
  let cred = Credential.OAuth({variant: "oauth", access: "oauth_acc_xyz", refresh: "refresh_abc", expires: 3600.0})
  let result = BearerToken.extract(cred)
  assertion(
    ~message=`Expected "Bearer oauth_acc_xyz", got "${result}"`,
    (a, b) => a == b,
    result,
    "Bearer oauth_acc_xyz",
  )
})

// BT3: Wellknown credential extracts Bearer token
test("BT3: Wellknown token extracts to Bearer token", () => {
  let cred = Credential.Wellknown({variant: "wellknown", key: "wk-key", token: "wk_token_xyz"})
  let result = BearerToken.extract(cred)
  assertion(
    ~message=`Expected "Bearer wk_token_xyz", got "${result}"`,
    (a, b) => a == b,
    result,
    "Bearer wk_token_xyz",
  )
})

// BT4: Env credential with present env var returns its value
test("BT4: Env credential with present env var returns value", () => {
  let cred = Credential.Env({variant: "env", envVar: "TEST_BEARER_TOKEN"})
  let result = BearerToken.extract(cred)
  // Node.processEnv lookup — value depends on environment at test runtime.
  // The env var TEST_BEARER_TOKEN should be set in the test runner environment.
  assertion(
    ~message=`BT4: Env credential did not return expected value`,
    (a, b) => a == b,
    result,
    "test_token_value",
  )
})

// BT5: Env credential with missing env var returns empty string
test("BT5: Env credential with missing env var returns empty string", () => {
  let cred = Credential.Env({variant: "env", envVar: "NON_EXISTENT_BEARER_TOKEN_VAR_12345"})
  let result = BearerToken.extract(cred)
  assertion(
    ~message=`Expected "", got "${result}"`,
    (a, b) => a == b,
    result,
    "",
  )
})
