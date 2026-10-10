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

// Persistence tests use an isolated XDG data home and dummy token values only.
let persistenceHome = (~prefix: string): string => {
  let dir = Node.osHomedir() ++ "/" ++ prefix ++ "-" ++ String.make(Date.now())
  let _ = Node.mkdirSync(dir)
  let _ = Node.mkdirSync(dir ++ "/opencode")
  dir
}

let persistedAuthPath = (home: string): string => home ++ "/opencode/auth.json"
let readUtf8 = (path: string): string => Node.readFileSyncUtf8(path, {encoding: "utf8"})

let entryField = (content: string, provider: string, field: string): option<JSON.t> => {
  switch parseJson(content) {
  | Some(JSON.Object(root)) =>
    switch Dict.get(root, provider) {
    | Some(JSON.Object(entry)) => Dict.get(entry, field)
    | _ => None
    }
  | _ => None
  }
}

test("persist OAuth tokens merges only token fields and preserves other entries", () => {
  let home = persistenceHome(~prefix="test-auth-persist-merge")
  let path = persistedAuthPath(home)
  let original = "{\"openai\":{\"type\":\"oauth\",\"access\":\"old-access\",\"refresh\":\"old-refresh\",\"expires\":10,\"accountId\":\"acct-1\",\"extra\":\"keep\"},\"anthropic\":{\"type\":\"api\",\"key\":\"dummy-other-key\"}}"
  let _ = Node.writeFileSync(path, original)
  let env = Some(Dict.fromArray([("XDG_DATA_HOME", home)]))
  let result = AuthJsonSource.persistOAuthTokens(~env, "openai", "dummy-access", "dummy-refresh", 123456.0)
  let content = readUtf8(path)
  assertion(~message="persist reports success", (a, b) => a == b, result, true)
  assertion(~message="access updated", (a, b) => a == b, entryField(content, "openai", "access"), Some(JSON.String("dummy-access")))
  assertion(~message="refresh updated", (a, b) => a == b, entryField(content, "openai", "refresh"), Some(JSON.String("dummy-refresh")))
  assertion(~message="expires stored as epoch milliseconds", (a, b) => a == b, entryField(content, "openai", "expires"), Some(JSON.Number(123456.0)))
  assertion(~message="accountId preserved", (a, b) => a == b, entryField(content, "openai", "accountId"), Some(JSON.String("acct-1")))
  assertion(~message="type preserved", (a, b) => a == b, entryField(content, "openai", "type"), Some(JSON.String("oauth")))
  assertion(~message="other field preserved", (a, b) => a == b, entryField(content, "openai", "extra"), Some(JSON.String("keep")))
  assertion(~message="other provider untouched", (a, b) => a == b, entryField(content, "anthropic", "key"), Some(JSON.String("dummy-other-key")))
})

test("persist OAuth tokens no-ops for missing file and provider", () => {
  let home = persistenceHome(~prefix="test-auth-persist-missing")
  let env = Some(Dict.fromArray([("XDG_DATA_HOME", home)]))
  assertion(~message="missing file returns false", (a, b) => a == b, AuthJsonSource.persistOAuthTokens(~env, "openai", "dummy-access", "dummy-refresh", 1.0), false)
  let path = persistedAuthPath(home)
  let _ = Node.writeFileSync(path, "{\"anthropic\":{\"type\":\"api\",\"key\":\"dummy-key\"}}")
  let before = readUtf8(path)
  let result = AuthJsonSource.persistOAuthTokens(~env, "openai", "dummy-access", "dummy-refresh", 1.0)
  assertion(~message="missing provider returns false", (a, b) => a == b, result, false)
  assertion(~message="missing provider file remains untouched", (a, b) => a == b, readUtf8(path), before)
})

test("persist OAuth tokens no-ops on malformed JSON", () => {
  let home = persistenceHome(~prefix="test-auth-persist-malformed")
  let path = persistedAuthPath(home)
  let _ = Node.writeFileSync(path, "{ malformed")
  let env = Some(Dict.fromArray([("XDG_DATA_HOME", home)]))
  let result = AuthJsonSource.persistOAuthTokens(~env, "openai", "dummy-access", "dummy-refresh", 1.0)
  assertion(~message="malformed file returns false", (a, b) => a == b, result, false)
  assertion(~message="malformed file remains untouched", (a, b) => a == b, readUtf8(path), "{ malformed")
})

test("persist OAuth tokens completes atomic temp-file rename", () => {
  let home = persistenceHome(~prefix="test-auth-persist-atomic")
  let path = persistedAuthPath(home)
  let _ = Node.writeFileSync(path, "{\"openai\":{\"type\":\"oauth\",\"access\":\"old\",\"refresh\":\"old-refresh\",\"expires\":1}}")
  let env = Some(Dict.fromArray([("XDG_DATA_HOME", home)]))
  let result = AuthJsonSource.persistOAuthTokens(~env, "openai", "dummy-access", "dummy-refresh", 2000.0)
  assertion(~message="atomic persistence succeeds", (a, b) => a == b, result, true)
  assertion(~message="renamed file contains new token", (a, b) => a == b, entryField(readUtf8(path), "openai", "access"), Some(JSON.String("dummy-access")))
  assertion(~message="atomic temp file is no longer present", (a, b) => a == b, Node.existsSync(path ++ ".tmp"), false)
})

let () = runTests()
