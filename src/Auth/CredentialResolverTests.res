// src/Auth/CredentialResolverTests.res
// Tests for CredentialResolver module — covers spec scenarios CR1 through CR5.
open RescriptTest

autoBoot := false

// ─── Helpers ─────────────────────────────────────────────────────────────────

let tmpDir = (): string => {
  let ts = String.make(Date.now())
  Node.osTmpdir() ++ "/cr-test-" ++ ts
}

let tmpAuthJsonPath = (dir: string): string => dir ++ "/opencode/auth.json"

let ensureOpencodeDir = (dir: string): unit => {
  // Create base dir and opencode subdir; ignore if already exists
  try {
    let _ = Node.mkdirSync(dir)
  } catch {
  | _ => ()
  }
  try {
    let _ = Node.mkdirSync(dir ++ "/opencode")
  } catch {
  | _ => ()
  }
}

// ─── CR1: auth.json present → resolver returns that credential ────────────────

testAsync("CR1: auth.json credential is returned", callback => {
  let dir = tmpDir()
  let authPath = tmpAuthJsonPath(dir)
  let content = JSON.Object(Dict.fromArray([
    ("openai", JSON.Object(Dict.fromArray([
      ("type", JSON.String("api")),
      ("key", JSON.String("sk-auth-json-key")),
    ]))),
  ]))->JSON.stringify

  // Create opencode subdir + write auth.json
  ensureOpencodeDir(dir)
  let _ = Node.writeFileSync(authPath, content)

  // Set XDG_DATA_HOME so Paths.getAuthJsonPath resolves to our temp auth.json
  let _ = Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  // Isolate pi's auth.json too, so the real ~/.pi/agent/auth.json never leaks in.
  let _ = Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  // Isolate Claude Code credentials too, so the real ~/.claude never leaks in.
  let _ = Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")
  let result = CredentialResolver.resolve("openai")

  let _ = result->Promise.then(cred => {
    let passed = cred == Some(Credential.Api({variant: "api", key: "sk-auth-json-key"}))
    assertion(
      ~message="CR1: Expected auth.json credential",
      (a, b) => a == b,
      true,
      passed,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="CR1: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

// ─── CR2: auth.json absent, env present → resolver returns env credential ───────

testAsync("CR2: env credential is returned when auth.json is absent", callback => {
  let dir = tmpDir()
  let authPath = tmpAuthJsonPath(dir)

  // Create opencode subdir + write empty auth.json
  ensureOpencodeDir(dir)
  let _ = Node.writeFileSync(authPath, "{}")

  // Set XDG_DATA_HOME to our temp dir + set OPENAI_API_KEY in process.env
  let _ = Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  // Isolate pi's auth.json too, so the real ~/.pi/agent/auth.json never leaks in.
  let _ = Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  // Isolate Claude Code credentials too, so the real ~/.claude never leaks in.
  let _ = Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")
  let _ = Dict.set(Node.processEnv, "OPENAI_API_KEY", "sk-env-key")

  let result = CredentialResolver.resolve("openai")

  let _ = result->Promise.then(cred => {
    let passed = cred == Some(Credential.Api({variant: "api", key: "sk-env-key"}))
    assertion(
      ~message="CR2: Expected env credential",
      (a, b) => a == b,
      true,
      passed,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="CR2: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

// ─── CR3: auth.json + env absent → resolver returns None ─────────────────────

testAsync("CR3: resolver returns None when all three sources are empty", callback => {
  let dir = tmpDir()
  let authPath = tmpAuthJsonPath(dir)

  // Create opencode subdir + write empty auth.json
  ensureOpencodeDir(dir)
  let _ = Node.writeFileSync(authPath, "{}")

  // Set XDG_DATA_HOME to our temp dir; ensure no API key
  let _ = Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  // Isolate pi's auth.json too, so the real ~/.pi/agent/auth.json never leaks in.
  let _ = Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  // Isolate Claude Code credentials too, so the real ~/.claude never leaks in.
  let _ = Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")
  let _ = Dict.delete(Node.processEnv, "OPENAI_API_KEY")

  let result = CredentialResolver.resolve("openai")

  let _ = result->Promise.then(cred => {
    // All three sources should be empty → None
    let passed = cred == None
    assertion(
      ~message="CR3: Expected None when all sources are empty",
      (a, b) => a == b,
      true,
      passed,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="CR3: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

// ─── CR4: all sources absent → individual sources return None ─────────────────

test("CR4: individual sources return None when empty", () => {
  let dir = tmpDir()
  let authPath = tmpAuthJsonPath(dir)

  // Create opencode subdir + write empty auth.json
  ensureOpencodeDir(dir)
  let _ = Node.writeFileSync(authPath, "{}")

  let injectedEnv = Dict.fromArray([
    ("XDG_DATA_HOME", dir),
    // no OPENAI_API_KEY
  ])

  let jsonResult = AuthJsonSource.getCredential("openai")
  let envResult = EnvSource.getCredential("openai", injectedEnv)

  let jsonNone = jsonResult == None
  let envNone = envResult == None
  assertion(
    ~message="CR4: auth.json and env both None",
    (a, b) => a == b,
    true,
    jsonNone && envNone,
  )
})

// ─── CR5: returns a Promise ───────────────────────────────────────────────────

testAsync("CR5: resolve returns a Promise", callback => {
  let result = CredentialResolver.resolve("openai")
  let _ = result->Promise.then(_cred => {
    assertion(
      ~message="CR5: resolve returns a Promise",
      (a, b) => a == b,
      true,
      true,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="CR5: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

// ─── CR3 (config fallback): auth.json + env null, config has credentials ─────────

testAsync("CR3: config credential is returned when auth.json + env are empty", callback => {
  let dir = tmpDir()
  ensureOpencodeDir(dir)

  // Empty auth.json so AuthJsonSource returns None
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")

  // ConfigLoader loads from process.cwd() + "/.opencode/quotas.json"
  // so we must create .opencode/quotas.json (not opencode/quotas.json)
  let _ = Node.mkdirSync(dir ++ "/.opencode")

  // Valid quotas.json with credentials.openai (schema uses "type", not "variant")
  let configContent = JSON.stringify(
    JSON.Object(Dict.fromArray([
      ("credentials", JSON.Object(Dict.fromArray([
        ("openai", JSON.Object(Dict.fromArray([
          ("type", JSON.String("api")),
          ("key", JSON.String("sk-cfg-key")),
        ]))),
      ]))),
    ])),
  )
  let _ = Node.writeFileSync(dir ++ "/.opencode/quotas.json", configContent)

  // Clear API key env var; set XDG_DATA_HOME so auth.json path resolves
  let _ = Dict.delete(Node.processEnv, "OPENAI_API_KEY")
  let _ = Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  // Isolate pi's auth.json too, so the real ~/.pi/agent/auth.json never leaks in.
  let _ = Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  // Isolate Claude Code credentials too, so the real ~/.claude never leaks in.
  let _ = Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")

  // chdir into temp dir so ConfigLoader loads our quotas.json via cwd
  let prevCwd = Node.processCwd()
  let _ = Node.processChdir(dir)

  let result = CredentialResolver.resolve("openai")

  let _ = result->Promise.then(cred => {
    // Restore cwd using the absolute path to the temp dir we can derive from dir
    let _ = Node.processChdir(dir)
    let expected = Some(Credential.Api({variant: "api", key: "sk-cfg-key"}))
    let passed = cred == expected
    assertion(
      ~message="CR3: Expected config credential from quotas.json",
      (a, b) => a == b,
      true,
      passed,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    let _ = Node.processChdir(prevCwd)
    assertion(~message="CR3: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

// ─── resolveOrEmpty tests ──────────────────────────────────────────────────

testAsync("ROE1: resolveOrEmpty returns [] when credential is None", callback => {
  let dir = tmpDir()
  let authPath = tmpAuthJsonPath(dir)
  ensureOpencodeDir(dir)
  let _ = Node.writeFileSync(authPath, "{}")
  let _ = Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  // Isolate pi's auth.json too, so the real ~/.pi/agent/auth.json never leaks in.
  let _ = Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  // Isolate Claude Code credentials too, so the real ~/.claude never leaks in.
  let _ = Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")
  let _ = Dict.delete(Node.processEnv, "NONEXISTENT_PROVIDER_KEY")

  let fnCalled = ref(false)
  let dummyFn = (_cred: Credential.credential): Promise.t<array<Domain.quotaData>> => {
    fnCalled.contents = true
    Promise.resolve([])
  }

  let result = CredentialResolver.resolveOrEmpty(~key="non-existent-provider", ~fn=dummyFn)

  let _ = result->Promise.then(arr => {
    let passed = arr == [] && fnCalled.contents == false
    assertion(
      ~message="ROE1: Expected [] and fn not called when credential is None",
      (a, b) => a == b,
      true,
      passed,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="ROE1: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

testAsync("ROE2: resolveOrEmpty calls fn when credential is Some", callback => {
  let dir = tmpDir()
  let authPath = tmpAuthJsonPath(dir)
  ensureOpencodeDir(dir)
  let _ = Node.writeFileSync(authPath, JSON.stringify(
    JSON.Object(Dict.fromArray([
      ("test-provider", JSON.Object(Dict.fromArray([
        ("type", JSON.String("api")),
        ("key", JSON.String("sk-test-key")),
      ]))),
    ]))
  ))
  let _ = Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  // Isolate pi's auth.json too, so the real ~/.pi/agent/auth.json never leaks in.
  let _ = Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  // Isolate Claude Code credentials too, so the real ~/.claude never leaks in.
  let _ = Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")

  let fnCalled = ref(false)
  let dummyFn = (_cred: Credential.credential): Promise.t<array<Domain.quotaData>> => {
    fnCalled.contents = true
    Promise.resolve([
      DomainFixtures.makeQuotaData(
        ~id="test",
        ~providerName="test",
        ~used=0.0,
        ~limit=None,
      ),
    ])
  }

  let result = CredentialResolver.resolveOrEmpty(~key="test-provider", ~fn=dummyFn)

  let _ = result->Promise.then(arr => {
    let passed = fnCalled.contents == true && Belt.Array.length(arr) == 1
    assertion(
      ~message="ROE2: Expected fn called and 1 quota returned",
      (a, b) => a == b,
      true,
      passed,
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="ROE2: Promise rejected unexpectedly", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

// ─── Source labels (S2) ───────────────────────────────────────────────────────
// `-l` shows where each credential came from: opencode | pi | claude-code |
// env | config. These tests inject the env dict and write fixtures under
// os.tmpdir(), so they never read the developer's real credentials.

let labelCounter = ref(0)

// A counter keeps two tests in the same millisecond from sharing a fixture dir.
let labelDir = (): string => {
  labelCounter := labelCounter.contents + 1
  let dir =
    Node.osTmpdir() ++
    "/cr-label-" ++
    String.make(Date.now()) ++
    "-" ++
    Int.toString(labelCounter.contents)
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
  dir
}

let labelEnv = (~dir: string, ~extra: array<(string, string)>=[]): dict<string> =>
  Dict.fromArray(
    Array.concat(
      [
        ("XDG_DATA_HOME", dir),
        ("PI_CODING_AGENT_DIR", dir ++ "/pi"),
        ("CLAUDE_CONFIG_DIR", dir ++ "/claude"),
      ],
      extra,
    ),
  )

let writeAuthEntry = (~dir: string, ~harness: string, ~key: string): unit => {
  let entry = JSON.stringify(
    JSON.Object(
      Dict.fromArray([
        (key, JSON.Object(Dict.fromArray([
          ("type", JSON.String("api")),
          ("key", JSON.String("sk-label-secret")),
        ]))),
      ]),
    ),
  )
  let path = harness === "pi" ? dir ++ "/pi/auth.json" : dir ++ "/opencode/auth.json"
  let _ = Node.writeFileSync(path, entry)
}

let writeClaudeCredentials = (~dir: string): unit => {
  let content = JSON.stringify(
    JSON.Object(
      Dict.fromArray([
        ("claudeAiOauth", JSON.Object(Dict.fromArray([
          ("accessToken", JSON.String("claude-access-secret")),
          ("expiresAt", JSON.Number(9999999999999.0)),
        ]))),
      ]),
    ),
  )
  let _ = Node.writeFileSync(dir ++ "/claude/.credentials.json", content)
}

let writeQuotasConfig = (~dir: string, ~content: string): string => {
  let path = dir ++ "/quotas.json"
  let _ = Node.writeFileSync(path, content)
  path
}

let labelOf = (~dir: string, ~extra: array<(string, string)>=[], ~configPath: string, key: string) =>
  CredentialResolver.firstOriginLabelWith(
    ~env=labelEnv(~dir, ~extra),
    ~configPath,
    key,
  )

test("S2: every origin maps to its published label", () => {
  assertion(
    ~message="opencode label",
    (a, b) => a == b,
    CredentialResolver.originLabel(#opencode),
    "opencode",
  )
  assertion(~message="pi label", (a, b) => a == b, CredentialResolver.originLabel(#pi), "pi")
  assertion(
    ~message="claude-code label",
    (a, b) => a == b,
    CredentialResolver.originLabel(#claudeCode),
    "claude-code",
  )
  assertion(~message="env label", (a, b) => a == b, CredentialResolver.originLabel(#env), "env")
  assertion(
    ~message="config label",
    (a, b) => a == b,
    CredentialResolver.originLabel(#config),
    "config",
  )
})

test("S2: opencode auth.json labels as opencode", () => {
  let dir = labelDir()
  writeAuthEntry(~dir, ~harness="opencode", ~key="openai")
  assertion(
    ~message="first source is opencode",
    (a, b) => a == b,
    labelOf(~dir, ~configPath=dir ++ "/quotas.json", "openai"),
    Some("opencode"),
  )
})

test("S2: pi auth.json labels as pi when opencode has nothing", () => {
  let dir = labelDir()
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")
  writeAuthEntry(~dir, ~harness="pi", ~key="openai-codex")
  assertion(
    ~message="first source is pi",
    (a, b) => a == b,
    labelOf(~dir, ~configPath=dir ++ "/quotas.json", "openai"),
    Some("pi"),
  )
})

test("S2: env credential labels as env", () => {
  let dir = labelDir()
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")
  assertion(
    ~message="first source is env",
    (a, b) => a == b,
    labelOf(
      ~dir,
      ~extra=[("OPENAI_API_KEY", "sk-env-secret")],
      ~configPath=dir ++ "/quotas.json",
      "openai",
    ),
    Some("env"),
  )
})

test("S2: quotas.json credential labels as config", () => {
  let dir = labelDir()
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")
  let configPath = writeQuotasConfig(
    ~dir,
    ~content=JSON.stringify(
      JSON.Object(
        Dict.fromArray([
          ("credentials", JSON.Object(Dict.fromArray([
            ("openai", JSON.Object(Dict.fromArray([
              ("type", JSON.String("api")),
              ("key", JSON.String("sk-config-secret")),
            ]))),
          ]))),
        ]),
      ),
    ),
  )
  assertion(
    ~message="first source is config",
    (a, b) => a == b,
    labelOf(~dir, ~configPath, "openai"),
    Some("config"),
  )
})

test("S2: Anthropic Claude Code login labels as claude-code", () => {
  let dir = labelDir()
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")
  writeClaudeCredentials(~dir)
  assertion(
    ~message="claude-code wins for anthropic",
    (a, b) => a == b,
    labelOf(~dir, ~configPath=dir ++ "/quotas.json", "anthropic"),
    Some("claude-code"),
  )
})

test("S2: only the first candidate is reported (opencode before pi)", () => {
  let dir = labelDir()
  writeAuthEntry(~dir, ~harness="opencode", ~key="openai")
  writeAuthEntry(~dir, ~harness="pi", ~key="openai-codex")
  assertion(
    ~message="default order reports opencode, not pi",
    (a, b) => a == b,
    labelOf(~dir, ~configPath=dir ++ "/quotas.json", "openai"),
    Some("opencode"),
  )
})

test("S2: credentialSources order moves pi to the front", () => {
  let dir = labelDir()
  writeAuthEntry(~dir, ~harness="opencode", ~key="openai")
  writeAuthEntry(~dir, ~harness="pi", ~key="openai-codex")
  let configPath = writeQuotasConfig(
    ~dir,
    ~content="{\"credentialSources\":[\"pi\",\"opencode\"]}",
  )
  assertion(
    ~message="configured order reports pi first",
    (a, b) => a == b,
    labelOf(~dir, ~configPath, "openai"),
    Some("pi"),
  )
})

test("S2: no candidate labels as None", () => {
  let dir = labelDir()
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")
  assertion(
    ~message="no source reports None",
    (a, b) => a == b,
    labelOf(~dir, ~configPath=dir ++ "/quotas.json", "openai"),
    None,
  )
})

test("S2: labels never contain credential material", () => {
  let dir = labelDir()
  writeAuthEntry(~dir, ~harness="opencode", ~key="openai")
  let label = labelOf(~dir, ~configPath=dir ++ "/quotas.json", "openai")
  let text = switch label {
  | Some(value) => value
  | None => ""
  }
  assertion(
    ~message=`label must not leak the key, got: ${text}`,
    (a, b) => a == b,
    String.includes(text, "sk-label-secret"),
    false,
  )
})

let () = runTests()
