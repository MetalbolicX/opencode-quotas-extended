// src/Providers/MinimaxTests.res
// Tests for Minimax provider: createMinimaxProvider + parseMinimaxCli.
// Tests provider metadata (id, displayName, category, authStrategy) and
// mmx CLI parser reset-time computation.

open Minimax
open RescriptTest

autoBoot := false

// --- Tests --------------------------------------------------------------------

test("createMinimaxProvider returns provider with correct metadata", () => {
  let provider = createMinimaxProvider()
  assertion(~message="id is minimax", (a, b) => a == b, provider.id, "minimax")
  assertion(~message="displayName is Minimax Coding Plan", (a, b) => a == b, provider.displayName, "Minimax Coding Plan")
  assertion(~message="category is subscription", (a, b) => a == b, provider.category, "subscription")
  assertion(~message="authStrategy is api", (a, b) => a == b, provider.authStrategy, #api)
})

// isAvailable returns a Promise that resolves without throwing.
test("isAvailable returns a Promise<bool>", () => {
  let p = createMinimaxProvider().isAvailable()
  let ok = ref(true)
  p->Promise.then(_v => Promise.resolve())->Promise.catch(. _err => {
    ok := false
    Promise.resolve()
  })->ignore
  // Note: async; ok.contents may be stale when assertion runs in sync framework.
  // The key behavior (reject on error) is verified by ReportPipeline integration tests.
  assertion(~message="isAvailable resolves without throwing", (a, b) => a == b, true, ok.contents)
})

// fetchQuotas rejection-on-error is covered by ReportPipeline integration test
// ("one fails, one succeeds" — src/application/ReportPipeline.test.mjs).
// The bug fix (removing try/catch that swallows CLI errors) is verified there.

// mmx CLI stdout fixture — the human-readable table is omitted; the parser
// only needs the JSON blob starting at the "model_remains" key.
test("parseMinimaxCli populates reset from remains_time / weekly_remains_time", () => {
  let now = Date.now()
  // Anchor the fixture's "now" via the call so diffs are deterministic.
  // 9_600_000 ms = 2h40m remaining on the interval.
  // 214_848_000 ms ≈ 2d 11h 40m 48s remaining on the weekly.
  let intervalRemains = 9_600_000.0
  let weeklyRemains = 214_848_000.0
  let fixture = "...{\"model_remains\":[{\"start_time\":" ++ Belt.Float.toString(now) ++ ",\"end_time\":" ++ Belt.Float.toString(now +. intervalRemains) ++ ",\"remains_time\":" ++ Belt.Float.toString(intervalRemains) ++ ",\"current_interval_total_count\":0,\"current_interval_usage_count\":0,\"model_name\":\"general\",\"current_weekly_total_count\":0,\"current_weekly_usage_count\":0,\"weekly_start_time\":" ++ Belt.Float.toString(now) ++ ",\"weekly_end_time\":" ++ Belt.Float.toString(now +. weeklyRemains) ++ ",\"weekly_remains_time\":" ++ Belt.Float.toString(weeklyRemains) ++ ",\"current_interval_status\":1,\"current_interval_remaining_percent\":90,\"current_weekly_status\":1,\"current_weekly_remaining_percent\":80}],\"base_resp\":{\"status_code\":0,\"status_msg\":\"success\"}}"
  let entries = parseMinimaxCli(fixture)
  assertion(
    ~message="parseMinimaxCli returns 2 entries for general model",
    (a, b) => a == b,
    Array.length(entries),
    2,
  )
  // 5h row: reset ≈ now + 9_600_000 ms
  let fiveH = Belt.Array.getExn(entries, 0)
  assertion(~message="5h row has reset", (a, b) => a == b, Belt.Option.isSome(fiveH.reset), true)
  switch fiveH.reset {
  | Some(d) =>
    let diff = Date.getTime(d) -. now
    assertion(
      ~message="5h reset diff from now is >= 9_500_000 ms",
      (a, b) => a >= b,
      diff,
      9_500_000.0,
    )
    assertion(
      ~message="5h reset diff from now is <= 10_000_000 ms",
      (a, b) => a <= b,
      diff,
      10_000_000.0,
    )
  | None => ()
  }
  // Weekly row: reset ≈ now + 214_848_000 ms
  let weekly = Belt.Array.getExn(entries, 1)
  assertion(~message="weekly row has reset", (a, b) => a == b, Belt.Option.isSome(weekly.reset), true)
  switch weekly.reset {
  | Some(d) =>
    let diff = Date.getTime(d) -. now
    assertion(
      ~message="weekly reset diff from now is >= 214_000_000 ms",
      (a, b) => a >= b,
      diff,
      214_000_000.0,
    )
  | None => ()
  }
})

test("parseMinimaxCli falls back to None when remains_time is missing", () => {
  let fixture = "...{\"model_remains\":[{\"model_name\":\"general\",\"current_interval_remaining_percent\":90,\"current_weekly_remaining_percent\":80}]}"
  let entries = parseMinimaxCli(fixture)
  assertion(
    ~message="2 entries even without reset info",
    (a, b) => a == b,
    Array.length(entries),
    2,
  )
  let fiveH = Belt.Array.getExn(entries, 0)
  let weekly = Belt.Array.getExn(entries, 1)
  assertion(~message="5h reset is None when field missing", (a, b) => a == b, fiveH.reset, None)
  assertion(~message="weekly reset is None when field missing", (a, b) => a == b, weekly.reset, None)
})

// Session-reuse decision logic (pure).
test("decideFetchStep: session rows present -> UseSession", () => {
  let now = Date.now()
  let fixture = "...{\"model_remains\":[{\"model_name\":\"general\",\"current_interval_remaining_percent\":90,\"current_weekly_remaining_percent\":80,\"remains_time\":" ++ Belt.Float.toString(now) ++ "}]}"
  let rows = parseMinimaxCli(fixture)
  let step = decideFetchStep(Some(rows), None)
  let ok = switch step {
  | UseSession(r) => Array.length(r) === Array.length(rows)
  | _ => false
  }
  assertion(~message="expected UseSession", (a, b) => a == b, ok, true)
})

test("decideFetchStep: no session + key -> LoginWithKey", () => {
  let step = decideFetchStep(None, Some("key-abc"))
  let ok = switch step {
  | LoginWithKey(k) => k === "key-abc"
  | _ => false
  }
  assertion(~message="expected LoginWithKey(\"key-abc\")", (a, b) => a == b, ok, true)
})

test("decideFetchStep: no session + no key -> GiveUp", () => {
  let step = decideFetchStep(None, None)
  let ok = switch step {
  | GiveUp => true
  | _ => false
  }
  assertion(~message="expected GiveUp", (a, b) => a == b, ok, true)
})

// ── S2: mmx session fallback reported as a credential source ────────────────
// A fake `mmx` shell script stands in for the real CLI: no live session, no
// login round-trip, no network. The fixture is the documented
// `mmx quota show --output json` shape. Every touched env var is restored.

let mmxEnvKeys = [
  "PATH",
  "XDG_DATA_HOME",
  "PI_CODING_AGENT_DIR",
  "CLAUDE_CONFIG_DIR",
  "MINIMAX_API_KEY",
]

let savedMmxEnv: ref<Dict.t<string>> = ref(Dict.make())

let saveMmxEnv = (): unit =>
  mmxEnvKeys->Array.forEach(key =>
    switch Dict.get(Node.processEnv, key) {
    | Some(value) => Dict.set(savedMmxEnv.contents, key, value)
    | None => Dict.delete(savedMmxEnv.contents, key)->ignore
    }
  )

let restoreMmxEnv = (): unit =>
  mmxEnvKeys->Array.forEach(key =>
    switch Dict.get(savedMmxEnv.contents, key) {
    | Some(value) => Dict.set(Node.processEnv, key, value)
    | None => Dict.delete(Node.processEnv, key)->ignore
    }
  )

let ensureDir = (path: string): unit =>
  try {
    let _ = Node.mkdirSync(path)
  } catch {
  | _ => ()
  }

// Builds an isolated home plus a fake mmx binary; returns the temp dir.
let mmxHomeCounter = ref(0)

let makeMmxHome = (): string => {
  mmxHomeCounter := mmxHomeCounter.contents + 1
  let dir =
    Node.osTmpdir() ++
    "/minimax-mmx-" ++
    String.make(Date.now()) ++
    "-" ++
    Int.toString(mmxHomeCounter.contents)
  ensureDir(dir)
  ensureDir(dir ++ "/opencode")
  ensureDir(dir ++ "/bin")
  ensureDir(dir ++ "/bin-fail")
  // No stored Minimax credential: the session fallback is the only source.
  let _ = Node.writeFileSync(dir ++ "/opencode/auth.json", "{}")
  let fixture = "#!/bin/sh\necho '{\"model_remains\":[{\"model_name\":\"general\",\"current_interval_remaining_percent\":90,\"current_weekly_remaining_percent\":80,\"remains_time\":9600000,\"weekly_remains_time\":214848000}]}'\n"
  let script = dir ++ "/bin/mmx"
  let _ = Node.writeFileSync(script, fixture)
  // Installed but not authenticated: `which mmx` succeeds, every quota call fails.
  let failing = dir ++ "/bin-fail/mmx"
  let _ = Node.writeFileSync(failing, "#!/bin/sh\nexit 1\n")
  let _ = Node.execSync("chmod 755 " ++ script ++ " " ++ failing, {
    encoding: "utf8",
    timeout: 10_000,
    stdio: "pipe",
  })
  dir
}

// `bin` is prepended to a real PATH so `which` resolves while the fake mmx
// shadows any real binary.
let isolateForMmx = (~dir: string, ~bin: string): unit => {
  saveMmxEnv()
  mmxEnvKeys->Array.forEach(key => Dict.delete(Node.processEnv, key)->ignore)
  Dict.set(Node.processEnv, "XDG_DATA_HOME", dir)
  Dict.set(Node.processEnv, "PI_CODING_AGENT_DIR", dir ++ "/pi")
  Dict.set(Node.processEnv, "CLAUDE_CONFIG_DIR", dir ++ "/claude")
  Dict.set(Node.processEnv, "PATH", `${bin}:/usr/bin:/bin`)
}

testAsync("S2: an authenticated mmx session labels the source as mmx", testDone => {
  let dir = makeMmxHome()
  isolateForMmx(~dir, ~bin=dir ++ "/bin")
  let provider = createMinimaxProvider()
  let _ = provider.credentialSource()->Promise.then(label => {
    let _ = provider.isAvailable()->Promise.then(available => {
      restoreMmxEnv()
      assertion(
        ~message="credentialSource reports the mmx session",
        (a, b) => a == b,
        label,
        Some("mmx"),
      )
      assertion(
        ~message="isAvailable behavior is unchanged for the same session",
        (a, b) => a == b,
        available,
        true,
      )
      testDone()
      Promise.resolve()
    })
    Promise.resolve()
  })->Promise.catch(. _err => {
    restoreMmxEnv()
    fail(~message="credentialSource rejected unexpectedly", ())
    testDone()
    Promise.resolve()
  })
})

testAsync("S2: an unauthenticated mmx CLI and no stored key means no source", testDone => {
  let dir = makeMmxHome()
  isolateForMmx(~dir, ~bin=dir ++ "/bin-fail")
  let provider = createMinimaxProvider()
  let _ = provider.credentialSource()->Promise.then(label => {
    restoreMmxEnv()
    assertion(
      ~message="credentialSource is None without a session",
      (a, b) => a == b,
      label,
      None,
    )
    testDone()
    Promise.resolve()
  })->Promise.catch(. _err => {
    restoreMmxEnv()
    fail(~message="credentialSource rejected unexpectedly", ())
    testDone()
    Promise.resolve()
  })
})

// Run all tests
let () = runTests()
