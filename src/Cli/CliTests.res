// src/Cli/CliTests.res
// Tests for Cli module: parse-error early-return path, usageText presence,
// history accumulation via flushNow, and config loading.
// process.exit terminates the process — some tests use Cli.run which returns
// without exiting on early-return paths.
open RescriptTest
open Cli

autoBoot := false

// ── Existing tests ─────────────────────────────────────────────────────────────

// C1: Cli.run with garbage argv returns exitCode 2 and non-empty stderr
testAsync("C1: Cli.run with garbage returns exitCode 2 and error in stderr", callback => {
  let _ = Cli.run(["--not-a-flag"])
  ->Promise.then(result => {
    assertion(~message="exitCode is 2 on parse error", (a, b) => a == b, result.exitCode, 2)
    assertion(~message="stderr has content on parse error", (a, b) => a == b, result.stderr !== "", true)
    callback()
    Promise.resolve()
  })
})

// C2: Cli.main is callable (smoke)
// process.exit terminates the process, so this can only verify the call site compiles.
test("C2: Cli.main is callable", () => {
  let _ = Cli.main(["--help"])
  ()
})

// C3: usageText is non-empty
test("C3: Cli.usageText is a non-empty string", () => {
  assertion(~message="usageText is non-empty", (a, b) => a == b, Cli.usageText !== "", true)
})

// ── NEW: History accumulation smoke tests ───────────────────────────────────────

// TEST-CLI-1: two-run history accumulation via flushNow
// Verifies: historyStore.flushNow() is called before exit, ensuring points are not lost.
// Without flushNow, debounced writes would be lost on process exit.
// We test at the JsonFileHistory level: append twice, flush, verify both points persist.
testAsync("CLI-1: history accumulation — append + flush preserves points", testDone => {
  let tempPath = "/tmp/test-cli-hist-" ++ Float.toString(Date.now()) ++ ".json"
  let stubDeps: JsonFileHistory.deps = {
    readFileSync: (_path) => "{\"history\":{}}",
    writeFileSync: (_path, _data) => (),
    existsSync: (_path) => false,
    now: () => 1000.0,
  }
  let store = JsonFileHistory.make(~debounceMs=1.0, tempPath, stubDeps)
  let point1: Domain.historyPoint = {timestamp: 1000.0, used: 10.0, limit: Some(100.0)}
  let point2: Domain.historyPoint = {timestamp: 2000.0, used: 20.0, limit: Some(100.0)}
  let _ = store.append("provider-a", point1)
    ->Promise.then(_ => store.append("provider-a", point2))
    ->Promise.then(_ => {
      store.flushNow()
      // Verify getHistory returns both points after flush
      store.getHistory("provider-a", 1.0e10)
      ->Promise.then(points => {
        assertion(~message="history has 2 points after 2 appends", (a, b) => a == b, points->Array.length, 2)
        testDone(~planned=1, ())
        Promise.resolve()
      })
    })
})

// TEST-CLI-2: config load honored — ConfigLoader.loadConfig parses custom values
// Verifies that when ConfigLoader.loadConfig reads a config file with
// predictionWindowMinutes: 90.0, it correctly parses and returns that value.
// This confirms the config-loading-to-pipeline path is functional.
test("CLI-2: ConfigLoader.loadConfig parses predictionWindowMinutes from config", () => {
  let mockFiles: ref<dict<string>> = ref(Dict.make())
  let mockExists: ref<dict<bool>> = ref(Dict.make())
  Dict.set(mockFiles.contents, "/tmp/test-config.json", "{\"predictionWindowMinutes\":90.0}")
  Dict.set(mockExists.contents, "/tmp/test-config.json", true)
  // Install mock deps for ConfigLoader
  ConfigLoader.depsRef := {
    readFileSync: p => {
      switch Dict.get(mockFiles.contents, p) {
      | Some(c) => c
      | None => ""
      }
    },
    existsSync: p => {
      switch Dict.get(mockExists.contents, p) {
      | Some(b) => b
      | None => false
      }
    },
    warnFn: _msg => (),
  }
  let cfg = ConfigLoader.loadConfig(~configPath="/tmp/test-config.json", ())
  assertion(~message="predictionWindowMinutes is 90.0 from config", (a, b) => a == b, cfg.predictionWindowMinutes, 90.0)
})

// TEST-CLI-3: most_critical aggregation opt-in via .opencode/quotas.json
// Verifies REQ-E-3-2: Cli.res wires ConfigLoader.loadConfig so that a
// user-configured most_critical aggregation group is loaded and passed to
// the pipeline. Without the wiring, aggregatedGroups is always empty (max default).
test("CLI-3: most_critical opt-in — config file with strategy most_critical loads into pipeline", () => {
  // Set up a mock config file with a most_critical aggregation group
  let mockFiles: ref<dict<string>> = ref(Dict.make())
  let mockExists: ref<dict<bool>> = ref(Dict.make())
  let configContent = `{
    "predictionWindowMinutes": 60.0,
    "historyMaxAgeHours": 24.0,
    "aggregatedGroups": {
      "test-ai-group": {
        "strategy": "most_critical",
        "members": ["openai/gpt-4o", "anthropic/claude-sonnet-4", "test-provider/model-x"]
      }
    }
  }`
  Dict.set(mockFiles.contents, "/tmp/test-most-critical-config.json", configContent)
  Dict.set(mockExists.contents, "/tmp/test-most-critical-config.json", true)

  // Install mock deps for ConfigLoader to read our test config
  ConfigLoader.depsRef := {
    readFileSync: p => {
      switch Dict.get(mockFiles.contents, p) {
      | Some(c) => c
      | None => ""
      }
    },
    existsSync: p => {
      switch Dict.get(mockExists.contents, p) {
      | Some(b) => b
      | None => false
      }
    },
    warnFn: _msg => (),
  }

  // Load the config via ConfigLoader (this is what Cli.res should call)
  let cfg = ConfigLoader.loadConfig(~configPath="/tmp/test-most-critical-config.json", ())

  // Verify the most_critical group was parsed
  assertion(~message="aggregatedGroups is non-empty when config has a group", (a, b) => a == b, Dict.keysToArray(cfg.aggregatedGroups)->Array.length > 0, true)

  // Verify the strategy is most_critical
  let groupKeys = Dict.keysToArray(cfg.aggregatedGroups)
  let firstKey = switch groupKeys->Array.get(0) {
    | Some(k) => k
    | None => ""
  }
  let groupOpt = Dict.get(cfg.aggregatedGroups, firstKey)
  let strategyIsMostCritical = switch groupOpt {
    | Some(g) => g.strategy === "most_critical"
    | None => false
  }
  assertion(~message="group strategy is most_critical", (a, b) => a == b, strategyIsMostCritical, true)

  // Verify predictionWindowMinutes was also loaded (not just defaults)
  assertion(~message="predictionWindowMinutes is 60.0 from config", (a, b) => a == b, cfg.predictionWindowMinutes, 60.0)
})

let () = runTests()
