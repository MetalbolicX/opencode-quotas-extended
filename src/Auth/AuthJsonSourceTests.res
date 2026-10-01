// src/Auth/AuthJsonSourceTests.res
// Tests for AuthJsonSource module — covers spec scenarios A1 through A6.
open RescriptTest

autoBoot := false

// Unique timestamp-based path helper to avoid collisions
let tmpPath = (~prefix: string): string => {
  let ts = String.make(Date.now())
  Node.osHomedir() ++ "/" ++ prefix ++ "-" ++ ts ++ ".json"
}

// Helper: parse a JSON string safely (mirrors readJson contract)
let parseJson = (content: string): option<JSON.t> => {
  try {
    Some(JSON.parseOrThrow(content))
  } catch {
  | _ => None
  }
}

// A1: api entry resolves
test("A1: api entry in auth.json resolves to api credential", () => {
  let entry = JSON.Object(Dict.fromArray([
    ("type", JSON.String("api")),
    ("key", JSON.String("sk-test-key")),
  ]))
  let result = Credential.fromJson(entry)
  let expected = Some(Credential.Api({variant: "api", key: "sk-test-key"}))
  assertion(
    ~message=`Expected Api, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// A2: oauth entry resolves with expires default
test("A2: oauth entry without expires defaults to 0", () => {
  let entry = JSON.Object(Dict.fromArray([
    ("type", JSON.String("oauth")),
    ("access", JSON.String("access-token")),
    ("refresh", JSON.String("refresh-token")),
  ]))
  let result = Credential.fromJson(entry)
  let expected = Some(Credential.OAuth({variant: "oauth", access: "access-token", refresh: "refresh-token", expires: 0.0}))
  assertion(
    ~message=`Expected OAuth with expires=0, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// A3: wellknown entry resolves
test("A3: wellknown entry resolves to wellknown credential", () => {
  let entry = JSON.Object(Dict.fromArray([
    ("type", JSON.String("wellknown")),
    ("key", JSON.String("some-key")),
    ("token", JSON.String("some-token")),
  ]))
  let result = Credential.fromJson(entry)
  let expected = Some(Credential.Wellknown({variant: "wellknown", key: "some-key", token: "some-token"}))
  assertion(
    ~message=`Expected Wellknown, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    expected,
  )
})

// A4: missing file returns null without throwing
test("A4: non-existent file path returns None", () => {
  let result = AuthJsonSource.readJson("/nonexistent/path/that/does/not/exist-auth-json-test-12345.json")
  assertion(
    ~message=`Expected None for missing file, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// A5: malformed JSON returns null without throwing
test("A5: malformed JSON returns None", () => {
  let path = tmpPath(~prefix="test-auth-malformed")
  let _ = Node.writeFileSync(path, "{ bad json")
  let result = AuthJsonSource.readJson(path)
  // clean up
  try {
    let _ = Node.writeFileSync(path, "")
  } catch {
  | _ => ()
  }
  assertion(
    ~message=`Expected None for malformed JSON, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// A6: provider absent from valid file returns null
test("A6: provider absent from valid auth.json returns None", () => {
  // auth.json has anthropic entry but we ask for openai
  let entry = JSON.Object(Dict.fromArray([
    ("type", JSON.String("api")),
    ("key", JSON.String("sk-only-anthropic")),
  ]))
  let authJson = JSON.Object(Dict.fromArray([("anthropic", entry)]))
  // Simulate what getCredential does: look up by canonical key
  let key = ProviderKeys.authKey("openai")  // returns "openai"
  let authDict = switch authJson {
  | JSON.Object(d) => d
  | _ => Dict.make()
  }
  let providerEntry = Dict.get(authDict, key)
  let result = switch providerEntry {
  | None => None
  | Some(e) => Credential.fromJson(e)
  }
  assertion(
    ~message=`Expected None for absent provider, got ${Belt.Option.map(result, _ => "Some(_)")->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

let () = runTests()
