// src/Auth/HarnessResolutionTests.res
// Multi-harness credential resolution (opencode + pi): ordering, union,
// credentialSources override, and candidate fallthrough.
// Every file lives under an isolated os.tmpdir() root; env is injected, never global.
open RescriptTest

autoBoot := false

let counter = ref(0)

// Creates <tmp>/<prefix>-<ts>-<n>/{opencode,pi,.opencode} and returns the root.
let makeRoot = (~prefix: string): string => {
  counter := counter.contents + 1
  let root =
    Node.osTmpdir() ++ "/" ++ prefix ++ "-" ++ String.make(Date.now()) ++ "-" ++ Int.toString(counter.contents)
  let _ = Node.mkdirSync(root)
  let _ = Node.mkdirSync(root ++ "/opencode")
  let _ = Node.mkdirSync(root ++ "/pi")
  let _ = Node.mkdirSync(root ++ "/.opencode")
  root
}

let cleanup = (root: string): unit => Node.rmSyncRecursive(root, {recursive: true, force: true})

let envFor = (root: string, ~extra: array<(string, string)>=[]): dict<string> =>
  Dict.fromArray(Array.concat([("XDG_DATA_HOME", root), ("PI_CODING_AGENT_DIR", root ++ "/pi")], extra))

let configPathFor = (root: string): string => root ++ "/.opencode/quotas.json"

let writeOpencode = (root: string, json: string) => Node.writeFileSync(root ++ "/opencode/auth.json", json)
let writePi = (root: string, json: string) => Node.writeFileSync(root ++ "/pi/auth.json", json)
let writeConfig = (root: string, json: string) => Node.writeFileSync(configPathFor(root), json)

let resolveIn = (root: string, ~extra: array<(string, string)>=[], providerId: string) =>
  CredentialResolver.resolveAllWith(~env=envFor(root, ~extra), ~configPath=configPathFor(root), providerId)

let origins = (cands: array<CredentialResolver.candidate>) => cands->Array.map(c => c.origin)

let api = (key: string) => Credential.Api({variant: "api", key})

let opencodeOpenAI = `{"openai":{"type":"oauth","access":"oc-access","refresh":"oc-refresh","expires":1}}`
let piOpenAI = `{"openai-codex":{"type":"oauth","access":"pi-access","refresh":"pi-refresh","expires":2,"accountId":"acct"}}`

// ─── Paths ────────────────────────────────────────────────────────────────────

test("pi auth path honors PI_CODING_AGENT_DIR", () => {
  let env = Some(Dict.fromArray([("PI_CODING_AGENT_DIR", "/custom/pi")]))
  assertion(~message="explicit dir", (a, b) => a == b, Paths.getPiAuthJsonPath(~env), "/custom/pi/auth.json")
})

test("pi auth path expands a leading ~ in PI_CODING_AGENT_DIR", () => {
  let path = Paths.getPiAuthJsonPath(~env=Some(Dict.fromArray([("PI_CODING_AGENT_DIR", "~/pi-alt")])))
  assertion(~message="no literal ~ left", (a, b) => a == b, String.startsWith(path, "~"), false)
  assertion(~message="tilde suffix kept", (a, b) => a == b, String.endsWith(path, "/pi-alt/auth.json"), true)
})

test("pi auth path defaults to ~/.pi/agent/auth.json", () => {
  let path = Paths.getPiAuthJsonPath(~env=Some(Dict.make()))
  assertion(~message="default agent dir", (a, b) => a == b, String.endsWith(path, "/.pi/agent/auth.json"), true)
})

// ─── pi key map ───────────────────────────────────────────────────────────────

test("pi key map uses pi's own provider ids", () => {
  let cases = [
    ("openai", Some("openai-codex")),
    ("opencode-go", Some("opencode-go")),
    ("zai-coding-plan", Some("zai")),
    ("minimax-coding-plan", Some("minimax")),
    ("kimi", Some("kimi-coding")),
    ("anthropic", None),
    ("gemini", None),
  ]
  cases->Array.forEach(((id, expected)) =>
    assertion(~message=`pi key for ${id}`, (a, b) => a == b, ProviderKeys.piAuthKey(id), expected)
  )
})

// ─── Resolution order and union ──────────────────────────────────────────────

test("both harnesses: opencode candidate first, then pi", () => {
  let root = makeRoot(~prefix="harness-both")
  let _ = writeOpencode(root, opencodeOpenAI)
  let _ = writePi(root, piOpenAI)
  let cands = resolveIn(root, "openai")
  cleanup(root)
  assertion(~message="order", (a, b) => a == b, origins(cands), [#opencode, #pi])
  assertion(
    ~message="pi credential decoded",
    (a, b) => a == b,
    cands->Array.get(1)->Option.map(c => c.credential),
    Some(Credential.OAuth({variant: "oauth", access: "pi-access", refresh: "pi-refresh", expires: 2.0})),
  )
})

test("provider only in pi still resolves (pi api_key entry)", () => {
  let root = makeRoot(~prefix="harness-pi-only")
  let _ = writeOpencode(root, "{}")
  let _ = writePi(root, `{"zai":{"type":"api_key","key":"pi-zai"}}`)
  let cands = resolveIn(root, "zai-coding-plan")
  cleanup(root)
  assertion(~message="pi-only zai", (a, b) => a == b, cands, [{credential: api("pi-zai"), origin: #pi}])
})

test("provider only in opencode still resolves", () => {
  let root = makeRoot(~prefix="harness-oc-only")
  let _ = writeOpencode(root, `{"kimi-for-coding":{"type":"api","key":"oc-kimi"}}`)
  let cands = resolveIn(root, "kimi")
  cleanup(root)
  assertion(~message="opencode-only kimi", (a, b) => a == b, cands, [{credential: api("oc-kimi"), origin: #opencode}])
})

test("env candidate comes after harness candidates", () => {
  let root = makeRoot(~prefix="harness-env")
  let _ = writeOpencode(root, opencodeOpenAI)
  let cands = resolveIn(root, ~extra=[("OPENAI_API_KEY", "sk-env")], "openai")
  cleanup(root)
  assertion(~message="opencode then env", (a, b) => a == b, origins(cands), [#opencode, #env])
})

test("pi anthropic entry is never a candidate", () => {
  let root = makeRoot(~prefix="harness-pi-anthropic")
  let _ = writePi(root, `{"anthropic":{"type":"oauth","access":"a","refresh":"r","expires":1}}`)
  let cands = resolveIn(root, "anthropic")
  cleanup(root)
  assertion(~message="no pi candidate", (a, b) => a == b, origins(cands)->Array.includes(#pi), false)
})

test("credentialSources reorders and filters harnesses", () => {
  let root = makeRoot(~prefix="harness-order")
  let _ = writeOpencode(root, opencodeOpenAI)
  let _ = writePi(root, piOpenAI)
  let _ = writeConfig(root, `{"credentialSources":["pi","opencode"]}`)
  let reordered = origins(resolveIn(root, "openai"))
  let _ = writeConfig(root, `{"credentialSources":["pi"]}`)
  let piOnly = origins(resolveIn(root, "openai"))
  cleanup(root)
  assertion(~message="pi first", (a, b) => a == b, reordered, [#pi, #opencode])
  assertion(~message="opencode excluded", (a, b) => a == b, piOnly, [#pi])
})

test("invalid quotas.json falls back to the default order without throwing", () => {
  let root = makeRoot(~prefix="harness-badcfg")
  let _ = writeOpencode(root, opencodeOpenAI)
  let _ = writePi(root, piOpenAI)
  let _ = writeConfig(root, `{"credentialSources":["bogus"]}`)
  let cands = try resolveIn(root, "openai") catch {
  | _ => []
  }
  cleanup(root)
  assertion(~message="default order", (a, b) => a == b, origins(cands), [#opencode, #pi])
})

test("credentialSources schema accepts harness names and rejects others", () => {
  let root = makeRoot(~prefix="harness-schema")
  let _ = writeConfig(root, `{"credentialSources":["pi"]}`)
  let valid = ConfigLoader.loadConfig(~configPath=configPathFor(root), ()).credentialSources
  let _ = writeConfig(root, `{"credentialSources":["bogus"]}`)
  let rejected = try {
    let _ = ConfigLoader.loadConfig(~configPath=configPathFor(root), ())
    false
  } catch {
  | _ => true
  }
  let _ = writeConfig(root, `{}`)
  let absent = ConfigLoader.loadConfig(~configPath=configPathFor(root), ()).credentialSources
  cleanup(root)
  assertion(~message="valid list kept", (a, b) => a == b, valid, Some(["pi"]))
  assertion(~message="unknown source rejected", (a, b) => a == b, rejected, true)
  assertion(~message="absent stays None", (a, b) => a == b, absent, None)
})

// ─── Fallthrough ──────────────────────────────────────────────────────────────

@new external jsError: string => exn = "Error"

let errorMessage = (err: exn): string =>
  switch JsExn.anyToExnInternal(err) {
  | JsExn(v) => Belt.Option.getWithDefault(JsExn.message(v), String.make(v))
  | e => String.make(e)
  }

let cand = (key: string, origin): CredentialResolver.candidate => {credential: api(key), origin}

let row = (id: string): Domain.quotaData =>
  DomainFixtures.makeQuotaData(~id, ~providerName=id, ~used=0.0, ~limit=None)

// Runs tryCandidates; fn maps a key to either an error message or a row id.
let run = (cands, outcome: string => result<string, string>, calls: ref<array<string>>) =>
  CredentialResolver.tryCandidates(cands, c => {
    let key = switch c.credential {
    | Credential.Api(a) => a.key
    | _ => "?"
    }
    calls := Array.concat(calls.contents, [key])
    switch outcome(key) {
    | Ok(id) => Promise.resolve([row(id)])
    | Error(msg) => Promise.reject(jsError(msg))
    }
  })

testAsync("auth failure (HTTP 401) falls through to the next candidate", callback => {
  let calls = ref([])
  run([cand("a", #opencode), cand("b", #pi)], k => k == "a" ? Error("HTTP 401: https://x") : Ok("from-b"), calls)
  ->Promise.then(rows => {
    assertion(~message="second candidate used", (a, b) => a == b, rows->Array.map(r => r.id), ["from-b"])
    assertion(~message="both tried in order", (a, b) => a == b, calls.contents, ["a", "b"])
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("HTTP 403 and expired-credential errors also fall through", callback => {
  let calls = ref([])
  run(
    [cand("a", #opencode), cand("b", #pi), cand("c", #env)],
    k =>
      switch k {
      | "a" => Error("HTTP 403: https://x")
      | "b" => Error("OpenAI token from pi " ++ CredentialResolver.expiredHint ++ " `pi` to refresh")
      | _ => Ok("from-c")
      },
    calls,
  )
  ->Promise.then(rows => {
    assertion(~message="third candidate used", (a, b) => a == b, rows->Array.map(r => r.id), ["from-c"])
    assertion(~message="all three tried", (a, b) => a == b, calls.contents, ["a", "b", "c"])
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("non-auth failure rejects without trying the next candidate", callback => {
  let calls = ref([])
  run([cand("a", #opencode), cand("b", #pi)], k => k == "a" ? Error("HTTP 500: https://x") : Ok("from-b"), calls)
  ->Promise.then(_ => {
    fail(~message="expected rejection", ())
    callback()
    Promise.resolve()
  })
  ->Promise.catch(err => {
    assertion(~message="original error kept", (a, b) => a == b, errorMessage(err), "HTTP 500: https://x")
    assertion(~message="second not tried", (a, b) => a == b, calls.contents, ["a"])
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("every candidate failing auth rejects with the last error", callback => {
  let calls = ref([])
  run([cand("a", #opencode), cand("b", #pi)], k => Error("HTTP 401: " ++ k), calls)
  ->Promise.then(_ => {
    fail(~message="expected rejection", ())
    callback()
    Promise.resolve()
  })
  ->Promise.catch(err => {
    assertion(~message="last error surfaced", (a, b) => a == b, errorMessage(err), "HTTP 401: b")
    assertion(~message="both tried", (a, b) => a == b, calls.contents, ["a", "b"])
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("no candidates resolves [] without calling fn", callback => {
  let calls = ref([])
  run([], _ => Ok("never"), calls)
  ->Promise.then(rows => {
    assertion(~message="empty", (a, b) => a == b, rows, [])
    assertion(~message="fn not called", (a, b) => a == b, calls.contents, [])
    callback()
    Promise.resolve()
  })
  ->ignore
})

let () = runTests()
