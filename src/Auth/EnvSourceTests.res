// src/Auth/EnvSourceTests.res
// Tests for EnvSource module — covers spec scenarios E1 through E4.
open RescriptTest

autoBoot := false

// E1: known provider with non-empty value
test("E1: openai with OPENAI_API_KEY returns api credential", () => {
  let env = Dict.fromArray([("OPENAI_API_KEY", "sk-abc123")])
  let result = EnvSource.getCredential("openai", env)
  let expected = Some(Credential.Api({variant: "api", key: "sk-abc123"}))
  assertion(
    ~message=`Expected Some(Api), got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// E2: unmapped provider returns null
test("E2: opencode-zen (unmapped) returns null", () => {
  let env = Dict.fromArray([("OPENAI_API_KEY", "sk-abc")])
  let result = EnvSource.getCredential("opencode-zen", env)
  assertion(
    ~message=`Expected None for unmapped provider, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// E3: mapped provider but var absent returns null
test("E3: openai with missing env var returns null", () => {
  let env = Dict.make()
  let result = EnvSource.getCredential("openai", env)
  assertion(
    ~message=`Expected None for missing var, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// E4: empty var value treated as missing
test("E4: openai with empty string env var returns null", () => {
  let env = Dict.fromArray([("OPENAI_API_KEY", "")])
  let result = EnvSource.getCredential("openai", env)
  assertion(
    ~message=`Expected None for empty var, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// E5: minimax with MINIMAX_API_KEY returns api credential
test("E5: minimax with MINIMAX_API_KEY returns api credential", () => {
  let env = Dict.fromArray([("MINIMAX_API_KEY", "mmx-key-123")])
  let result = EnvSource.getCredential("minimax", env)
  let expected = Some(Credential.Api({variant: "api", key: "mmx-key-123"}))
  assertion(
    ~message=`Expected Some(Api), got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// E6: kimi with KIMI_API_KEY returns api credential (REQ-K-6)
test("E6: kimi with KIMI_API_KEY returns api credential", () => {
  let env = Dict.fromArray([("KIMI_API_KEY", "k-123456")])
  let result = EnvSource.getCredential("kimi", env)
  let expected = Some(Credential.Api({variant: "api", key: "k-123456"}))
  assertion(
    ~message=`Expected Some(Api), got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// E7: kimi with KIMI_API_KEY unset or empty returns None (REQ-K-6)
test("E7: kimi with KIMI_API_KEY unset returns None", () => {
  let env = Dict.make()
  let result = EnvSource.getCredential("kimi", env)
  assertion(
    ~message=`Expected None for unset var, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

test("E7b: kimi with KIMI_API_KEY empty string returns None", () => {
  let env = Dict.fromArray([("KIMI_API_KEY", "")])
  let result = EnvSource.getCredential("kimi", env)
  assertion(
    ~message=`Expected None for empty var, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

let () = runTests()
