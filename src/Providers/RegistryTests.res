// src/Providers/RegistryTests.res
// Tests for ProviderRegistry: buildDefaultRegistry, ids, get, all.
// R1: buildDefaultRegistry returns registry with all 8 providers.
// R2: registry.get("openai") returns Some(OpenAI provider).
// R3: registry.get("unknown") returns None.
// R4: registry.ids() returns 8 ids.

open Registry
open RescriptTest

autoBoot := false

test("buildDefaultRegistry returns registry with all 8 providers", () => {
  let reg = buildDefaultRegistry()
  assertion(
    ~message="8 provider ids",
    (a, b) => a == b,
    reg.ids()->Array.length,
    8,
  )
})

test("registry.ids() contains openai", () => {
  let reg = buildDefaultRegistry()
  let ids = reg.ids()
  assertion(
    ~message="ids includes openai",
    (a, b) => a == b,
    ids->Array.some(id => id == "openai"),
    true,
  )
})

test("registry.get(\"openai\") returns Some(provider)", () => {
  let reg = buildDefaultRegistry()
  let openaiProv = reg.get("openai")
  assertion(
    ~message="openai provider is Some",
    (a, b) => a == b,
    Belt.Option.isSome(openaiProv),
    true,
  )
})

test("registry.get(\"unknown-xyz\") returns None", () => {
  let reg = buildDefaultRegistry()
  let unknown = reg.get("unknown-xyz")
  assertion(
    ~message="unknown provider is None",
    (a, b) => a == b,
    Belt.Option.isNone(unknown),
    true,
  )
})

test("registry.all() returns 8 providers", () => {
  let reg = buildDefaultRegistry()
  assertion(
    ~message="all() returns 8 providers",
    (a, b) => a == b,
    reg.all()->Array.length,
    8,
  )
})

test("buildDefaultRegistryWith accepts deps and returns same registry", () => {
  let deps: deps = {credentialResolver: None, httpClient: None}
  let reg = buildDefaultRegistryWith(deps)
  assertion(
    ~message="injected registry has 8 providers",
    (a, b) => a == b,
    reg.ids()->Array.length,
    8,
  )
})

test("buildDefaultRegistryWith with Some(deps) returns same registry", () => {
  let deps: deps = {
    credentialResolver: Some("stub-resolver"),
    httpClient: Some("stub-http"),
  }
  let reg = buildDefaultRegistryWith(deps)
  assertion(
    ~message="injected registry with deps still has 8 providers",
    (a, b) => a == b,
    reg.ids()->Array.length,
    8,
  )
})

let () = runTests()
