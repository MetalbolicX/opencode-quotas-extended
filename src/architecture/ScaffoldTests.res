// src/architecture/ScaffoldTests.res
// Architecture guard: verifies the committed source tree layout.
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
// The ReScript migration retained the original PascalCase adapter directories
// and added architecture, bindings, and testing support at src/.
let expectedDirs: array<string> = [
  "src/architecture",
  "src/Auth",
  "src/bindings",
  "src/Cli",
  "src/Infra",
  "src/Providers",
  "src/testing",
  "src/domain",
  "src/ports",
  "src/application",
  "src/rendering",
  "src/i18n",
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

  let expected = [
    "architecture",
    "Auth",
    "bindings",
    "Cli",
    "domain",
    "i18n",
    "Infra",
    "integration",
    "ports",
    "Providers",
    "rendering",
    "testing",
  ]

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
