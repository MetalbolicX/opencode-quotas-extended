// src/Auth/ConfigSourceTests.res
// Tests for ConfigSource module — covers spec scenarios C1 through C4.
open RescriptTest

autoBoot := false

// Helper: make a quotasConfig with only credentials field set
let makeConfig = (~credentials: option<JSON.t>): ConfigLoader.quotasConfig => {
  let defaults = ConfigLoader.defaults
  {...defaults, credentials}
}

// C1: api entry resolves
test("C1: api credential entry resolves to Api variant", () => {
  let credJson = JSON.Object(Dict.fromArray([
    ("type", JSON.String("api")),
    ("key", JSON.String("sk-test-key")),
  ]))
  let config = makeConfig(~credentials=Some(JSON.Object(Dict.fromArray([
    ("openai", credJson),
  ]))))
  let result = ConfigSource.getCredential(config, "openai")
  let expected = Some(Credential.Api({variant: "api", key: "sk-test-key"}))
  assertion(
    ~message=`Expected Api credential, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// C2: env entry resolves
test("C2: env credential entry resolves to Env variant", () => {
  let credJson = JSON.Object(Dict.fromArray([
    ("type", JSON.String("env")),
    ("envVar", JSON.String("MY_API_KEY")),
  ]))
  let config = makeConfig(~credentials=Some(JSON.Object(Dict.fromArray([
    ("custom-provider", credJson),
  ]))))
  let result = ConfigSource.getCredential(config, "custom-provider")
  let expected = Some(Credential.Env({variant: "env", envVar: "MY_API_KEY"}))
  assertion(
    ~message=`Expected Env credential, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// C3: no credentials field returns null
test("C3: config with no credentials field returns null", () => {
  let config = makeConfig(~credentials=None)
  let result = ConfigSource.getCredential(config, "openai")
  assertion(
    ~message=`Expected None for missing credentials, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// C4: provider missing from map returns null
test("C4: credentials exist but provider is absent returns null", () => {
  let credJson = JSON.Object(Dict.fromArray([
    ("type", JSON.String("api")),
    ("key", JSON.String("sk-other")),
  ]))
  let config = makeConfig(~credentials=Some(JSON.Object(Dict.fromArray([
    ("anthropic", credJson),
  ]))))
  let result = ConfigSource.getCredential(config, "openai")
  assertion(
    ~message=`Expected None for missing provider, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

let () = runTests()
