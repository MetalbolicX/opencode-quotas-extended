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

let () = runTests()
