// src/architecture/DomainPurityTests.res
// Architecture guard: domain layer must have zero I/O imports.
// This test mirrors tests/architecture/domain-purity.test.ts in ReScript.
open RescriptTest

autoBoot := false

// ── Helpers ────────────────────────────────────────────────────────────────────

// Recursively walk a directory and collect all .res file paths.
let walkResFiles = (dir: string): array<string> => {
  let results: array<string> = []
  let entries = Node.readdirSync(dir, { withFileTypes: true })
  let rec recurse = (subdir: string) => {
    let subEntries = Node.readdirSync(subdir, { withFileTypes: true })
    Belt.Array.forEach(subEntries, entry => {
      let full = Node.pathJoin(subdir, entry.name)
      if entry.isDirectory() {
        recurse(full)
      } else if String.endsWith(entry.name, ".res") {
        results->Belt.Array.push(full)->ignore
      }
    })
  }
  Belt.Array.forEach(entries, entry => {
    let full = Node.pathJoin(dir, entry.name)
    if entry.isDirectory() {
      recurse(full)
    } else if String.endsWith(entry.name, ".res") {
      results->Belt.Array.push(full)->ignore
    }
  })
  results
}

// Read a text file as a string (UTF-8).
let readText = (path: string): string => {
  Node.readFileSyncUtf8(path, {encoding: "utf-8"})
}

// Check whether a source string contains any forbidden import patterns.
let containsForbidden = (src: string, forbidden: array<string>): option<string> => {
  let rec check = (i: int): option<string> => {
    if i >= Belt.Array.length(forbidden) {
      None
    } else {
      let pat = Belt.Array.getExn(forbidden, i)
      if String.includes(src, pat) {
        Some(pat)
      } else {
        check(i + 1)
      }
    }
  }
  check(0)
}

// ── Domain files under test ────────────────────────────────────────────────────

// All domain .res files (recursive) — the guard walks src/domain/** .
let domainDir = Node.pathJoin(Node.processCwd(), "src/domain")

// ── Tests ─────────────────────────────────────────────────────────────────────

test("domain .res files contain zero forbidden I/O imports", () => {
  let files = walkResFiles(domainDir)
  assertion(
    ~message=`Expected to find domain .res files, found ${Belt.Array.length(files)->Belt.Int.toString}`,
    (a, _b) => a > 0,
    Belt.Array.length(files),
    0,
  )

  let forbidden = [
    "node:fs",
    "node:path",
    "node:os",
    "node:net",
    "node:http",
    "node:https",
    "node:child_process",
    "node:perf_hooks",
    "fetch(",
    "cross-fetch",
    "node-fetch",
    "src/ports",
    "src/adapters",
    "src/services",
    "src/cli",
    "src/plugin",
  ]

  let rec checkFiles = (i: int, failures: int): int => {
    if i >= Belt.Array.length(files) {
      failures
    } else {
      let file = Belt.Array.getExn(files, i)
      let src = readText(file)
      switch containsForbidden(src, forbidden) {
      | Some(pat) =>
        let msg = `Domain file "${file}" contains forbidden pattern "${pat}"`
        assertion(~message=msg, (a, b) => a == b, true, false)
        checkFiles(i + 1, failures + 1)
      | None => checkFiles(i + 1, failures)
      }
    }
  }

  let failures = checkFiles(0, 0)
  assertion(
    ~message=`Zero forbidden imports expected, found ${Belt.Int.toString(failures)} violations`,
    (a, b) => a == b,
    failures,
    0,
  )
})

let () = runTests()
