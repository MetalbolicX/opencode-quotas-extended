// src/architecture/TestIsolationGuardTests.res
// Architecture guard: test-suite filesystem isolation.
// Test helpers must never touch the user's real home directory. Tests that need
// a writable HOME-like root must derive it from Node.osTmpdir() so every run is
// self-cleaning and nothing accumulates in $HOME (bug: test-auth-persist-* and
// test-auth-malformed-*.json leaked into $HOME on every suite run).
open RescriptTest

autoBoot := false

// Recursively collect all *Tests.res sources under src/ (Tests files INCLUDED —
// unlike TypeSafetyGuardsTests, which walks production sources only).
let walkTestSources = (dir: string): array<string> => {
  let results: array<string> = []
  let rec recurse = (subdir: string) => {
    let entries = Node.readdirSync(subdir, { withFileTypes: true })
    Belt.Array.forEach(entries, entry => {
      let full = Node.pathJoin(subdir, entry.name)
      if entry.isDirectory() {
        recurse(full)
      } else if String.endsWith(entry.name, "Tests.res") {
        results->Belt.Array.push(full)->ignore
      }
    })
  }
  recurse(dir)
  results
}

let offendingSources = (): array<string> => {
  walkTestSources(Node.pathJoin(Node.processCwd(), "src"))
  ->Belt.Array.keep(path =>
    // Skip this guard itself: its assertion message cites the forbidden helper by name.
    String.endsWith(path, "TestIsolationGuardTests.res")
      ? false
      : String.includes(Node.readFileSyncUtf8(path, {encoding: "utf-8"}), "osHomedir")
  )
}

let joinComma = (items: array<string>): string =>
  items->Belt.Array.reduce("", (acc, s) => acc === "" ? s : acc ++ ", " ++ s)

test("test sources never reference osHomedir (isolate under osTmpdir)", () => {
  let offenders = offendingSources()
  assertion(
    ~message=`Tests must not use Node.osHomedir(); derive roots from Node.osTmpdir() instead. Offending files: ${joinComma(offenders)}`,
    (a, b) => a == b,
    offenders->Belt.Array.length,
    0,
  )
})

let () = runTests()
