// src/Providers/CredentialSourceTests.res
// S2 behavior tests: every provider reports the first locally selected
// credential source, using exactly the resolution key its isAvailable uses.
// All fixtures live under os.tmpdir() and are injected through process env
// (restored on the way out), so no real credential file is ever read and no
// network call is made.
open RescriptTest

autoBoot := false

// ── Environment isolation ────────────────────────────────────────────────────

let isolatedKeys = [
  "PATH",
  "XDG_DATA_HOME",
  "PI_CODING_AGENT_DIR",
  "CLAUDE_CONFIG_DIR",
  "OPENAI_API_KEY",
  "ANTHROPIC_API_KEY",
  "GEMINI_API_KEY",
  "MINIMAX_API_KEY",
  "KIMI_API_KEY",
]

let savedEnv: ref<Dict.t<string>> = ref(Dict.make())

// Saves every key we are about to touch, then points the process at an isolated
// home. restoreEnv() puts the originals back, so a failure cannot leak state.
let saveAndIsolate = (dir: string): unit => {
  isolatedKeys->Array.forEach(key => {
    switch Dict.get(Node.processEnv, key) {
    | Some(value) => Dict.set(savedEnv.contents, key, value)
    | None => Dict.delete(savedEnv.contents, key)->ignore
    }
  })
  isolatedKeys->Array.forEach(key => Dict.delete(Node.processEnv, key)->ignore)
  Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")
  // A PATH with no mmx binary keeps Minimax's session fallback off.
  Dict.set(Node.processEnv, "PATH", dir ++ "/empty-bin")
}

let restoreEnv = (): unit => {
  isolatedKeys->Array.forEach(key => {
    switch Dict.get(savedEnv.contents, key) {
    | Some(value) => Dict.set(Node.processEnv, key, value)
    | None => Dict.delete(Node.processEnv, key)->ignore
    }
  })
}

let dirCounter = ref(0)

let makeDir = (): string => {
  dirCounter := dirCounter.contents + 1
  let dir =
    Node.osTmpdir() ++
    "/cred-source-" ++
    String.make(Date.now()) ++
    "-" ++
    Int.toString(dirCounter.contents)
  let ensure = (path: string): unit => {
    try {
      let _ = Node.mkdirSync(path)
    } catch {
    | _ => ()
    }
  }
  ensure(dir)
  ensure(dir ++ "/opencode")
  ensure(dir ++ "/pi")
  ensure(dir ++ "/claude")
  ensure(dir ++ "/empty-bin")
  dir
}

let writeAuthJson = (~dir: string, ~entries: array<(string, string)>): unit => {
  let dict = Dict.make()
  entries->Array.forEach(((providerKey, key)) => {
    Dict.set(
      dict,
      providerKey,
      JSON.Object(
        Dict.fromArray([("type", JSON.String("api")), ("key", JSON.String(key))]),
      ),
    )
  })
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", JSON.stringify(JSON.Object(dict)))
}

// ── Registry under the isolated home ─────────────────────────────────────────

type case = {provider: Provider.quotaProvider, entryKey: string}

// Every registered provider paired with the auth.json key it resolves through.
// Auth keys come from ProviderKeys: "go" → opencode-go, "zai" → zai-coding-plan,
// "kimi" → kimi-for-coding, "minimax" → minimax-coding-plan,
// "gemini" → google-gemini, "openai"/"anthropic" → themselves.
let cases: array<case> = [
  {provider: OpenAI.createOpenAIProvider(), entryKey: "openai"},
  {provider: Go.createGoProvider(), entryKey: "opencode-go"},
  {provider: Zai.createZaiProvider(), entryKey: "zai-coding-plan"},
  {provider: Kimi.createKimiProvider(), entryKey: "kimi-for-coding"},
  {provider: Minimax.createMinimaxProvider(), entryKey: "minimax-coding-plan"},
  {provider: Anthropic.createAnthropicProvider(), entryKey: "anthropic"},
  {provider: Gemini.createGeminiProvider(), entryKey: "google-gemini"},
]

let providerLabel = (provider: Provider.quotaProvider): Promise.t<option<string>> =>
  provider.credentialSource()->Promise.catch(. _err => Promise.resolve(None))

let providerAvailable = (provider: Provider.quotaProvider): Promise.t<bool> =>
  provider.isAvailable()->Promise.catch(. _err => Promise.resolve(false))

// ── Tests ────────────────────────────────────────────────────────────────────

testAsync("S2: every provider labels its opencode credential as opencode", testDone => {
  let dir = makeDir()
  saveAndIsolate(dir)
  writeAuthJson(~dir, ~entries=cases->Array.map(c => (c.entryKey, "sk-fixture-key")))

  let rec check = (index: int, failures: array<string>): Promise.t<array<string>> => {
    switch Belt.Array.get(cases, index) {
    | None => Promise.resolve(failures)
    | Some(c) =>
      let label = providerLabel(c.provider)
      label->Promise.then(value => {
        let next = value == Some("opencode")
          ? failures
          : Belt.Array.concat(failures, [`${c.provider.id}: ${Belt.Option.getWithDefault(value, "None")}`])
        check(index + 1, next)
      })
    }
  }

  let _ = check(0, [])->Promise.then(failures => {
    restoreEnv()
    assertion(
      ~message=`all 7 providers must label opencode, mismatches: ${Js.Array.joinWith(", ", failures)}`,
      (a, b) => a == b,
      failures->Array.length,
      0,
    )
    testDone()
    Promise.resolve()
  })
})

testAsync("S2: provider credentialSource agrees with isAvailable (same keys)", testDone => {
  let dir = makeDir()
  saveAndIsolate(dir)
  writeAuthJson(~dir, ~entries=cases->Array.map(c => (c.entryKey, "sk-fixture-key")))

  let rec check = (index: int, failures: array<string>): Promise.t<array<string>> => {
    switch Belt.Array.get(cases, index) {
    | None => Promise.resolve(failures)
    | Some(c) =>
      let available = providerAvailable(c.provider)
      available->Promise.then(isAvail => {
        let label = providerLabel(c.provider)
        label->Promise.then(value => {
          let consistent = isAvail === Belt.Option.isSome(value)
          let next = consistent
            ? failures
            : Belt.Array.concat(failures, [
                `${c.provider.id}: isAvailable=${isAvail ? "true" : "false"} label=${Belt.Option.getWithDefault(value, "None")}`,
              ])
          check(index + 1, next)
        })
      })
    }
  }

  let _ = check(0, [])->Promise.then(failures => {
    restoreEnv()
    assertion(
      ~message=`credentialSource must track isAvailable, mismatches: ${Js.Array.joinWith(", ", failures)}`,
      (a, b) => a == b,
      failures->Array.length,
      0,
    )
    testDone()
    Promise.resolve()
  })
})

testAsync("S2: no stored credential and no mmx means no source", testDone => {
  let dir = makeDir()
  saveAndIsolate(dir)
  writeAuthJson(~dir, ~entries=[])

  let _ = providerLabel(Minimax.createMinimaxProvider())->Promise.then(value => {
    restoreEnv()
    assertion(
      ~message="Minimax reports no source without a key or an mmx session",
      (a, b) => a == b,
      value,
      None,
    )
    testDone()
    Promise.resolve()
  })
})

test("S2: real provider credentialSource uses the resolver key, not the id", () => {
  // go resolves through "opencode-go" and minimax through "minimax-coding-plan";
  // a provider that used its own id would report no source here.
  let dir = makeDir()
  saveAndIsolate(dir)
  writeAuthJson(~dir, ~entries=[("opencode-go", "sk-go"), ("minimax-coding-plan", "sk-mmx")])
  let goLabel = CredentialResolver.firstOriginLabelWith(
    ~env=Node.processEnv,
    ~configPath=dir ++ "/quotas.json",
    "opencode-go",
  )
  let minimaxLabel = CredentialResolver.firstOriginLabelWith(
    ~env=Node.processEnv,
    ~configPath=dir ++ "/quotas.json",
    "minimax-coding-plan",
  )
  let unknownLabel = CredentialResolver.firstOriginLabelWith(
    ~env=Node.processEnv,
    ~configPath=dir ++ "/quotas.json",
    "nonexistent-provider",
  )
  restoreEnv()
  assertion(~message="go resolves through opencode-go", (a, b) => a == b, goLabel, Some("opencode"))
  assertion(
    ~message="minimax resolves through minimax-coding-plan",
    (a, b) => a == b,
    minimaxLabel,
    Some("opencode"),
  )
  assertion(
    ~message="an unknown key does not resolve",
    (a, b) => a == b,
    unknownLabel,
    None,
  )
})

let () = runTests()
