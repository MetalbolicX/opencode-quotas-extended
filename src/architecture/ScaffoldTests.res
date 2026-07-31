// src/architecture/ScaffoldTests.res
// Architecture guard: verifies the committed source tree layout.
// NOTE: legacy/ directory will be added by WU-5 (post-WU-4a merge).
// This guard checks only the current state; a future guard will assert legacy/.
open RescriptTest

autoBoot := false

// ── Helpers ────────────────────────────────────────────────────────────────────

let dirExists = (dir: string): bool => {
  let full = Node.pathJoin(Node.processCwd(), dir)
  if !Node.existsSync(full) {
    false
  } else {
    // statSync gives us a dirEnt with isDirectory()
    let stat = Node.statSync(full)
    stat.isDirectory()
  }
}

// ── Expected directories ───────────────────────────────────────────────────────
//
// WU-5 added:
//   "legacy"
// WU-6 removed vitest tests/ directory. The test runner is now the ReScript
// aggregate runner (scripts/run-tests.mjs) which discovers src/**/*Tests.res.mjs.
let expectedDirs: array<string> = [
  "src/domain",
  "src/ports",
  "src/application",
  "src/adapters/auth",
  "src/adapters/infra",
  "src/adapters/providers",
  "src/rendering",
  "src/i18n/locales",
  "src/cli",
  "src/integration",
  "legacy",
  "schemas",
  "scripts",
]

// ── Tests ─────────────────────────────────────────────────────────────────────

test("all expected source directories exist", () => {
  let rec checkAll = (i: int, missing: array<string>): array<string> => {
    if i >= Belt.Array.length(expectedDirs) {
      missing
    } else {
      let dir = Belt.Array.getExn(expectedDirs, i)
      if dirExists(dir) {
        checkAll(i + 1, missing)
      } else {
        checkAll(i + 1, Belt.Array.concat(missing, [dir]))
      }
    }
  }

  let missing = checkAll(0, [])
  if Belt.Array.length(missing) > 0 {
    let msg = "Missing directories: " ++ Js.Array.joinWith(", ", missing)
    assertion(~message=msg, (a, b) => a == b, 0, Belt.Array.length(missing))
  } else {
    assertion(
      ~message="All expected directories present",
      (a, b) => a == b,
      Belt.Array.length(expectedDirs),
      Belt.Array.length(expectedDirs),
    )
  }
})

test("src/ top-level folders match expected set", () => {
  let srcPath = Node.pathJoin(Node.processCwd(), "src")
  let entries = Node.readdirSync(srcPath, { withFileTypes: true })
  let dirNames = Belt.Array.keep(entries, e => e.isDirectory())->Belt.Array.map(e => e.name)

  let expected = ["domain", "ports", "application", "adapters", "rendering", "i18n", "cli"]

  let rec checkDirs = (i: int, missing: array<string>): array<string> => {
    if i >= Belt.Array.length(expected) {
      missing
    } else {
      let exp = Belt.Array.getExn(expected, i)
      if Belt.Array.getBy(dirNames, n => n == exp)->Belt.Option.isSome {
        checkDirs(i + 1, missing)
      } else {
        checkDirs(i + 1, Belt.Array.concat(missing, [exp]))
      }
    }
  }

  let missing = checkDirs(0, [])
  if Belt.Array.length(missing) > 0 {
    let msg = "src/ missing folders: " ++ Js.Array.joinWith(", ", missing)
    assertion(~message=msg, (a, b) => a == b, 0, Belt.Array.length(missing))
  } else {
    assertion(
      ~message="All expected src/ top-level folders present",
      (a, b) => a == b,
      Belt.Array.length(expected),
      Belt.Array.length(expected),
    )
  }
})

let () = runTests()
