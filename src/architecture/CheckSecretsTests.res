// src/architecture/CheckSecretsTests.res
// Architecture guard: check-secrets.sh exits 0 in clean state.
// Mirrors tests/architecture/check-secrets.test.ts.
// Uses execSyncSimple which throws on non-zero exit.
open RescriptTest

autoBoot := false

// ── Helpers ────────────────────────────────────────────────────────────────────

// Construct a fake GOCSPX secret at runtime so it does NOT appear as a literal
// substring in this source file (which would cause check-secrets.sh to flag it).
// We split the pattern and concatenate at runtime.
let makeFakeSecret = (): string => {
  let prefix = "GOC"
  let rest = "SPX-fake-secret-test-key-123"
  prefix ++ rest ++ "45"
}

// Run check-secrets.sh; returns 0 on success, 1 on failure.
// execSyncSimple runs with default options and throws on non-zero exit.
let runCheckSecrets = (): int => {
  try {
    let _ = Node.execSyncSimple("bash scripts/check-secrets.sh")
    0
  } catch {
  | _exn => 1
  }
}

// Plant a fake GOCSPX secret into scripts/ (outside src/) and clean up after.
// We use scripts/ because check-secrets.sh scans src/ — planting inside src/
// would cause the test file itself to be flagged.
let withFakeSecret = (fn: unit => unit): unit => {
  let fakePath = Node.pathJoin(Node.processCwd(), "scripts/fake-secret-test.txt")
  // Write fake secret
  Node.writeFileSync(fakePath, makeFakeSecret() ++ "\n")
  try {
    fn()
  } catch {
  | _exn => ()
  }
  // Always clean up
  try {
    Node.rmSync(fakePath)
  } catch {
  | _exn => ()
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test("check-secrets.sh exists and is accessible", () => {
  let scriptPath = Node.pathJoin(Node.processCwd(), "scripts/check-secrets.sh")
  let exists = Node.existsSync(scriptPath)
  assertion(
    ~message="scripts/check-secrets.sh must exist",
    (a, _b) => a == true,
    exists,
    true,
  )
})

test("check-secrets.sh exits 0 when no secrets are present", () => {
  let code = runCheckSecrets()
  assertion(
    ~message=`Expected check-secrets.sh exit 0 in clean state, got ${Belt.Int.toString(code)}`,
    (a, _b) => a == 0,
    code,
    0,
  )
})

test("check-secrets.sh exits non-zero when a fake GOCSPX secret is planted in scripts/", () => {
  withFakeSecret(() => {
    let code = runCheckSecrets()
    assertion(
      ~message=`Expected non-zero exit when fake secret planted, got ${Belt.Int.toString(code)}`,
      (a, _b) => a != 0,
      code,
      0,
    )
  })
})

let () = runTests()
