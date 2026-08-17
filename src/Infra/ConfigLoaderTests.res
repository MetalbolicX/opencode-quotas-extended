// src/Infra/ConfigLoaderTests.res
// Tests for ConfigLoader — 10 tests covering loadConfig and resolveAnthropicOrgId.
open RescriptTest

autoBoot := false

// ─── Mock deps helpers ────────────────────────────────────────────────────────

type mockDeps = {
  files: ref<dict<string>>,
  exists: ref<dict<bool>>,
  warnings: ref<array<string>>,
}

let makeMockDeps = (): mockDeps => {
  files: ref(Dict.make()),
  exists: ref(Dict.make()),
  warnings: ref([]),
}

let installDeps = (mock: mockDeps) => {
  ConfigLoader.depsRef := {
    readFileSync: p => {
      switch Dict.get(mock.files.contents, p) {
      | Some(c) => c
      | None => ""
      }
    },
    existsSync: p => {
      switch Dict.get(mock.exists.contents, p) {
      | Some(b) => b
      | None => false
      }
    },
    warnFn: msg => {
      mock.warnings := Belt.Array.concat(mock.warnings.contents, [msg])
    },
  }
}

// ─── Test 1: missing file returns defaults ────────────────────────────────────

test("missing file returns defaults", () => {
  let mock = makeMockDeps()
  // /test/quotas.json does NOT exist in mock.exists
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  assertion(
    ~message="displayMode should be #table from defaults",
    (a, b) => a == b,
    result.displayMode,
    #table,
  )
  assertion(
    ~message="disabled should be empty array",
    (a, b) => a == b,
    result.disabled,
    [],
  )
  assertion(
    ~message="historyMaxAgeHours should be 24",
    (a, b) => a == b,
    result.historyMaxAgeHours,
    24.0,
  )
})

// ─── Test 2: valid config merged with defaults ────────────────────────────────

test("valid config merged with defaults", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"displayMode": "json"}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  assertion(
    ~message="displayMode should be #json from user config",
    (a, b) => a == b,
    result.displayMode,
    #json,
  )
  assertion(
    ~message="disabled should be defaults (empty array)",
    (a, b) => a == b,
    result.disabled,
    [],
  )
  assertion(
    ~message="historyMaxAgeHours should be 24 from defaults",
    (a, b) => a == b,
    result.historyMaxAgeHours,
    24.0,
  )
})

// ─── Test 3: unknown top-level field rejected ─────────────────────────────────

test("unknown top-level field rejected", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"displayMode": "json", "foo": 123}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let threw = ref(false)
  try {
    let _ = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
    threw := false
  } catch {
  | ConfigLoader.ConfigValidationError(_) => threw := true
  | _ => threw := false
  }
  assertion(~message="unknown field should throw ConfigValidationError", (a, b) => a == b, threw.contents, true)
})

// ─── Test 4: partial progressBar deep-merged ──────────────────────────────────

test("partial progressBar deep-merged", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"progressBar": {"width": 30}}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  assertion(
    ~message="width should be 30 from user config",
    (a, b) => a == b,
    result.progressBar.width,
    30.0,
  )
  assertion(
    ~message="filledChar should be default █",
    (a, b) => a == b,
    result.progressBar.filledChar,
    "█",
  )
  assertion(
    ~message="emptyChar should be default .",
    (a, b) => a == b,
    result.progressBar.emptyChar,
    ".",
  )
  assertion(
    ~message="color should be default true",
    (a, b) => a == b,
    result.progressBar.color,
    true,
  )
})

// ─── Test 5: deprecated show stripped with warning ─────────────────────────────

test("deprecated show stripped with warning", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"show": true}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  assertion(
    ~message="show should be None (stripped)",
    (a, b) => a == b,
    result.show,
    None,
  )
  assertion(
    ~message="should have emitted deprecation warning for 'show'",
    (a, b) => String.includes(a, b),
    mock.warnings.contents->Array.joinUnsafe(", "),
    "show",
  )
})

// ─── Test 6: deprecated pollingInterval stripped with warning ──────────────────

test("deprecated pollingInterval stripped with warning", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"pollingInterval": 30}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  assertion(
    ~message="pollingInterval should be 0.0 (stripped, defaults applied)",
    (a, b) => a == b,
    result.pollingInterval,
    0.0,
  )
  assertion(
    ~message="should have emitted deprecation warning for 'pollingInterval'",
    (a, b) => String.includes(a, b),
    mock.warnings.contents->Array.joinUnsafe(", "),
    "pollingInterval",
  )
})

// ─── Test 7: anthropicOrgId from config wins ───────────────────────────────────

test("anthropicOrgId from config wins", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"anthropic": {"orgId": "cfg-org"}}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let cfg = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  let auth: option<dict<dict<string>>> = Some(Dict.make())
  let env: option<dict<string>> = Some(Dict.make())
  let result = ConfigLoader.resolveAnthropicOrgId(cfg, ~auth, ~env, ())
  assertion(~message="cfg orgId should win", (a, b) => a == b, result, "cfg-org")
})

// ─── Test 8: anthropicOrgId falls back to auth ────────────────────────────────

test("anthropicOrgId falls back to auth", () => {
  let mock = makeMockDeps()
  // Config has no anthropic
  Dict.set(mock.files.contents, "/test/quotas.json", `{}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let cfg = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  let authDict = Dict.make()
  let authProvider = Dict.make()
  Dict.set(authProvider, "orgId", "auth-org")
  Dict.set(authDict, "anthropic", authProvider)
  let auth: option<dict<dict<string>>> = Some(authDict)
  let env: option<dict<string>> = Some(Dict.make())
  let result = ConfigLoader.resolveAnthropicOrgId(cfg, ~auth, ~env, ())
  assertion(~message="auth orgId should be used as fallback", (a, b) => a == b, result, "auth-org")
})

// ─── Test 9: anthropicOrgId falls back to env ─────────────────────────────────

test("anthropicOrgId falls back to env", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let cfg = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  let envDict = Dict.make()
  Dict.set(envDict, "ANTHROPIC_ORG_ID", "env-org")
  let env: option<dict<string>> = Some(envDict)
  let result = ConfigLoader.resolveAnthropicOrgId(cfg, ~auth=None, ~env, ())
  assertion(~message="env orgId should be used as fallback", (a, b) => a == b, result, "env-org")
})

// ─── Test 10: anthropicOrgId missing throws ────────────────────────────────────

test("anthropicOrgId missing throws", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let cfg = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  let threw = ref(false)
  let _ = try {
    let _ = ConfigLoader.resolveAnthropicOrgId(cfg, ~auth=None, ~env=None, ())
    threw := false
  } catch {
  | ConfigLoader.ConfigValidationError(_) => threw := true
  | _ => threw := false
  }
  assertion(
    ~message="missing orgId in all sources should throw ConfigValidationError",
    (a, b) => a == b,
    threw.contents,
    true,
  )
})

// ─── Test 11: aggregatedGroups with strategy and members decoded correctly ─────────

test("aggregatedGroups decoded with strategy and members", () => {
  let mock = makeMockDeps()
  Dict.set(
    mock.files.contents,
    "/test/quotas.json",
    `{"aggregatedGroups": {"group1": {"strategy": "max", "members": ["a", "b"]}}}`,
  )
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  let groups = result.aggregatedGroups
  assertion(
    ~message="aggregatedGroups keys should include group1",
    (a, b) => a == b,
    Dict.keysToArray(groups),
    ["group1"],
  )
  let group1 = switch Dict.get(groups, "group1") {
  | Some(g) => g
  | None => {strategy: "", members: []}
  }
  assertion(~message="strategy should be max", (a, b) => a == b, group1.strategy, "max")
  assertion(~message="members should be [a, b]", (a, b) => a == b, group1.members, ["a", "b"])
})

// ─── Test 12: partial config missing optional fields returns defaults ─────────────

test("partial config missing optional fields returns defaults", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  assertion(
    ~message="showUnaggregated should be default false",
    (a, b) => a == b,
    result.showUnaggregated,
    false,
  )
  assertion(
    ~message="predictionWindowMinutes should be default 60",
    (a, b) => a == b,
    result.predictionWindowMinutes,
    60.0,
  )
  assertion(
    ~message="predictionShortWindowMinutes should be default 5",
    (a, b) => a == b,
    result.predictionShortWindowMinutes,
    5.0,
  )
  assertion(
    ~message="aggregatedGroups should be empty dict from defaults",
    (a, b) => a == b,
    Dict.keysToArray(result.aggregatedGroups)->Array.length,
    0,
  )
})

// ─── Test 13: missing config file warns with the searched path ─────────────────

test("missing config file warns with the searched path", () => {
  let mock = makeMockDeps()
  // /test/quotas.json does NOT exist in mock.exists (returns false by default)
  installDeps(mock)
  let result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  // Still returns defaults
  assertion(
    ~message="displayMode should be #table from defaults",
    (a, b) => a == b,
    result.displayMode,
    #table,
  )
  // But a warning must have been emitted mentioning the path
  let warningText = mock.warnings.contents->Array.joinUnsafe(", ")
  assertion(
    ~message=`Expected warning to mention searched path, got: ${warningText}`,
    (a, _b) => String.includes(a, "/test/quotas.json"),
    warningText,
    "",
  )
})

// ─── Test 14: existing config file does NOT warn ───────────────────────────────

test("existing config file does NOT warn", () => {
  let mock = makeMockDeps()
  Dict.set(mock.files.contents, "/test/quotas.json", `{"displayMode": "json"}`)
  Dict.set(mock.exists.contents, "/test/quotas.json", true)
  installDeps(mock)
  let _result = ConfigLoader.loadConfig(~configPath="/test/quotas.json", ())
  let warningText = mock.warnings.contents->Array.joinUnsafe(", ")
  assertion(
    ~message=`Expected no warning for existing file, got: ${warningText}`,
    (a, b) => a == b,
    warningText,
    "",
  )
})

let () = runTests()
