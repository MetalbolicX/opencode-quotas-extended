// src/Auth/ClaudeCodeSourceTests.res
// Tests for ClaudeCodeSource: read-only decode of Claude Code's
// .credentials.json (claudeAiOauth) under an isolated CLAUDE_CONFIG_DIR.
// Never touches the real ~/.claude/.credentials.json.
open RescriptTest

autoBoot := false

let counter = ref(0)

// Creates <tmp>/claude-src-<ts>-<n>/ and returns it.
let makeDir = (): string => {
  counter := counter.contents + 1
  let root =
    Node.osTmpdir() ++ "/claude-src-" ++ String.make(Date.now()) ++ "-" ++ Int.toString(counter.contents)
  let _ = Node.mkdirSync(root)
  root
}

let cleanup = (root: string): unit => Node.rmSyncRecursive(root, {recursive: true, force: true})

let envFor = (root: string): dict<string> => Dict.fromArray([("CLAUDE_CONFIG_DIR", root)])

let writeCreds = (root: string, json: string): unit =>
  Node.writeFileSync(root ++ "/.credentials.json", json)

// ─── Decoding ─────────────────────────────────────────────────────────────────

test("decodes claudeAiOauth into an OAuth credential", () => {
  let dir = makeDir()
  let _ = writeCreds(
    dir,
    `{"claudeAiOauth":{"accessToken":"cc-access","refreshToken":"cc-refresh","expiresAt":1735689600000,"refreshTokenExpiresAt":1736294400000,"scopes":["user:inference"],"subscriptionType":"max","rateLimitTier":"default"}}`,
  )
  let cred = ClaudeCodeSource.getCredential(~env=Some(envFor(dir)))
  cleanup(dir)
  assertion(
    ~message="access/refresh/expires decoded",
    (a, b) => a == b,
    cred,
    Some(Credential.OAuth({variant: "oauth", access: "cc-access", refresh: "cc-refresh", expires: 1735689600000.0})),
  )
})

test("missing .credentials.json returns None", () => {
  let dir = makeDir()
  let cred = ClaudeCodeSource.getCredential(~env=Some(envFor(dir)))
  cleanup(dir)
  assertion(~message="no file → None", (a, b) => a == b, cred, None)
})

test("malformed JSON returns None", () => {
  let dir = makeDir()
  let _ = writeCreds(dir, "{not-json")
  let cred = ClaudeCodeSource.getCredential(~env=Some(envFor(dir)))
  cleanup(dir)
  assertion(~message="bad JSON → None", (a, b) => a == b, cred, None)
})

test("missing claudeAiOauth returns None", () => {
  let dir = makeDir()
  let _ = writeCreds(dir, `{"other":{"accessToken":"nope"}}`)
  let cred = ClaudeCodeSource.getCredential(~env=Some(envFor(dir)))
  cleanup(dir)
  assertion(~message="no claudeAiOauth → None", (a, b) => a == b, cred, None)
})

test("claudeAiOauth without accessToken returns None", () => {
  let dir = makeDir()
  let _ = writeCreds(dir, `{"claudeAiOauth":{"refreshToken":"r","expiresAt":1}}`)
  let cred = ClaudeCodeSource.getCredential(~env=Some(envFor(dir)))
  cleanup(dir)
  assertion(~message="no access token → None", (a, b) => a == b, cred, None)
})

let () = runTests()
