// src/architecture/TypeSafetyGuardsTests.res
// Architecture guard: type-safety invariants (Obj.magic, %raw budget, .resi coverage).
// Consolidates tests/architecture/type-safety-guards.test.ts (Obj.magic, %raw, CROSS_MODULE)
// and tests/architecture/resi-coverage.test.ts (Phase 1 modules + DomainFixtures).
open RescriptTest

autoBoot := false

// ── Helpers ────────────────────────────────────────────────────────────────────

let projectRoot = Node.processCwd()
let srcDir = Node.pathJoin(projectRoot, "src")

let readFile = (path: string): string => {
  Node.readFileSyncUtf8(path, {encoding: "utf-8"})
}

let fileExists = (path: string): bool => {
  Node.existsSync(path)
}

// Recursively walk a directory and collect .res file paths, excluding *Tests.res.
let walkResFiles = (dir: string): array<string> => {
  let results: array<string> = []
  let entries = Node.readdirSync(dir, { withFileTypes: true })
  let rec recurse = (subdir: string) => {
    let subEntries = Node.readdirSync(subdir, { withFileTypes: true })
    Belt.Array.forEach(subEntries, entry => {
      let full = Node.pathJoin(subdir, entry.name)
      if entry.isDirectory() {
        recurse(full)
      } else if String.endsWith(entry.name, ".res") && !String.includes(entry.name, "Tests.res") {
        results->Belt.Array.push(full)->ignore
      }
    })
  }
  Belt.Array.forEach(entries, entry => {
    let full = Node.pathJoin(dir, entry.name)
    if entry.isDirectory() {
      recurse(full)
    } else if String.endsWith(entry.name, ".res") && !String.includes(entry.name, "Tests.res") {
      results->Belt.Array.push(full)->ignore
    }
  })
  results
}

// Count occurrences of a substring in a string.
// NOTE: Js.String.split is (separator, string) in ReScript 12 — data-last.
// (The previous (src, pat) call silently computed pat.split(src) and always
// returned 0, making both architecture guards vacuous.)
let countSubstring = (src: string, pat: string): int => {
  let parts = Js.String.split(pat, src)
  Belt.Array.length(parts) - 1
}

// ── Obj.magic guard ────────────────────────────────────────────────────────────

test("src/**/*.res (excluding *Tests.res) contains ZERO Obj.magic occurrences", () => {
  let files = walkResFiles(srcDir)
  assertion(
    ~message=`Expected to find .res files, found ${Belt.Array.length(files)->Belt.Int.toString}`,
    (a, _b) => a > 0,
    Belt.Array.length(files),
    0,
  )

  let rec checkFiles = (i: int, total: int, violations: array<string>): (int, array<string>) => {
    if i >= Belt.Array.length(files) {
      (total, violations)
    } else {
      let file = Belt.Array.getExn(files, i)
      let content = readFile(file)
      let count = countSubstring(content, "Obj.magic")
      if count > 0 {
        let v = `${file}: ${Belt.Int.toString(count)}x`
        checkFiles(i + 1, total + count, Belt.Array.concat(violations, [v]))
      } else {
        checkFiles(i + 1, total, violations)
      }
    }
  }

  let (total, violations) = checkFiles(0, 0, [])
  if total > 0 {
    let msg = "Obj.magic count must be 0. Found " ++ Belt.Int.toString(total) ++ " in:\n" ++ Js.Array.joinWith("\n", violations)
    assertion(~message=msg, (a, _b) => a == 0, total, 0)
  } else {
    assertion(
      ~message="Zero Obj.magic occurrences",
      (a, _b) => a == 0,
      total,
      0,
    )
  }
})

// ── %raw budget ───────────────────────────────────────────────────────────────

// %raw was fully eliminated (raw-to-typed-migration): use typed stdlib APIs or
// FFI externals instead. This guard keeps it that way.
test("src/**/*.res (excluding *Tests.res) contains ZERO %raw occurrences", () => {
  let files = walkResFiles(srcDir)
  assertion(
    ~message=`Expected to find .res files, found ${Belt.Array.length(files)->Belt.Int.toString}`,
    (a, _b) => a > 0,
    Belt.Array.length(files),
    0,
  )

  let rec checkFiles = (i: int, total: int, details: array<string>): (int, array<string>) => {
    if i >= Belt.Array.length(files) {
      (total, details)
    } else {
      let file = Belt.Array.getExn(files, i)
      let content = readFile(file)
      let count = countSubstring(content, "%raw")
      if count > 0 {
        let detail = file ++ ": " ++ Belt.Int.toString(count) ++ "x"
        checkFiles(i + 1, total + count, Belt.Array.concat(details, [detail]))
      } else {
        checkFiles(i + 1, total, details)
      }
    }
  }

  let (total, details) = checkFiles(0, 0, [])
  if total > 0 {
    let msg = "%raw count must be 0. Found " ++ Belt.Int.toString(total) ++ " in:\n" ++ Js.Array.joinWith("\n", details)
    assertion(~message=msg, (a, _b) => a == 0, total, 0)
  } else {
    assertion(
      ~message="Zero %raw occurrences",
      (a, _b) => a == 0,
      total,
      0,
    )
  }
})

// ── CROSS_MODULE_MODULES ───────────────────────────────────────────────────────
//
// Modules that cross module boundaries and must each have a .resi interface file.
// Updated to reflect Phase 6 completion; Filter module handled separately (WU-4b).
let crossModuleModules: array<string> = [
  // domain
  "domain/Types",
  "domain/Aggregation",
  "domain/Prediction",
  "domain/Reset",
  "domain/AggregationDefaults",
  "domain/Domain",
  // testing
  "testing/DomainFixtures",
  // provider port
  "Provider",
  // providers
  "Providers/Registry",
  "Providers/OpenAI",
  "Providers/Zen",
  "Providers/Go",
  "Providers/Zai",
  "Providers/Kimi",
  "Providers/Minimax",
  "Providers/Anthropic",
  "Providers/Gemini",
  // infra
  "Infra/ConfigLoader",
  "Infra/FetchHttp",
  "Infra/JsonFileHistory",
  "Infra/Paths",
  "Infra/Infra",
  // cli
  "Cli/Cli",
  "Cli/ParseArgs",
  "Cli/Messages",
  // rendering
  "rendering/Renderers",
  "rendering/Colors",
  // i18n
  "i18n/Translator",
  // bindings
  "bindings/Node",
  // auth
  "Auth/Auth",
  "Auth/Credential",
  "Auth/CredentialResolver",
]

test("every CROSS_MODULE module has a corresponding .resi interface file", () => {
  let rec checkAll = (i: int, missing: array<string>): array<string> => {
    if i >= Belt.Array.length(crossModuleModules) {
      missing
    } else {
      let modulePath = Belt.Array.getExn(crossModuleModules, i)
      let resPath = Node.pathJoin(srcDir, modulePath ++ ".res")
      let resiPath = Node.pathJoin(srcDir, modulePath ++ ".resi")
      if !fileExists(resPath) {
        let msg = `.res file missing: ${resPath}`
        checkAll(i + 1, Belt.Array.concat(missing, [msg]))
      } else if !fileExists(resiPath) {
        let msg = `.resi file missing: ${resiPath}`
        checkAll(i + 1, Belt.Array.concat(missing, [msg]))
      } else {
        checkAll(i + 1, missing)
      }
    }
  }

  let missing = checkAll(0, [])
  if Belt.Array.length(missing) > 0 {
    let msg = "Missing .resi files:\n" ++ Js.Array.joinWith("\n", missing)
    assertion(~message=msg, (a, _b) => a == 0, Belt.Array.length(missing), 0)
  } else {
    assertion(
      ~message="All CROSS_MODULE modules have .resi files",
      (a, _b) => a == 0,
      0,
      0,
    )
  }
})

// ── DomainFixtures.resi factory functions ───────────────────────────────────────

test("DomainFixtures.resi exposes all 4 required factory functions", () => {
  let resiPath = Node.pathJoin(srcDir, "testing/DomainFixtures.resi")
  let content = readFile(resiPath)

  let required = [
    "makeQuotaData",
    "makeHistoryPoint",
    "makeQuotaSnapshot",
    "makeAggregationGroup",
  ]

  let rec checkAll = (i: int, missing: array<string>): array<string> => {
    if i >= Belt.Array.length(required) {
      missing
    } else {
      let fn = Belt.Array.getExn(required, i)
      if String.includes(content, fn) {
        checkAll(i + 1, missing)
      } else {
        checkAll(i + 1, Belt.Array.concat(missing, [fn]))
      }
    }
  }

  let missing = checkAll(0, [])
  if Belt.Array.length(missing) > 0 {
    let msg = "DomainFixtures.resi missing factories: " ++ Js.Array.joinWith(", ", missing)
    assertion(~message=msg, (a, _b) => a == 0, Belt.Array.length(missing), 0)
  } else {
    assertion(
      ~message="DomainFixtures.resi exposes all 4 factories",
      (a, _b) => a == 0,
      0,
      0,
    )
  }
})

let () = runTests()
