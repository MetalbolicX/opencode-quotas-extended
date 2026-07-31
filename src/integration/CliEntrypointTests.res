// src/integration/CliEntrypointTests.res
// Integration test: CLI entrypoint smoke — spawns the built CLI and verifies --help.
// This mirrors tests/integration/cli-entrypoint.test.ts in ReScript.
// Bucket A: port — ReScript source exists (Node.execSync), child process is feasible.
// INV-2: only exercises --help and --list flags; no credential or network activity.
open RescriptTest

autoBoot := false

// ── helpers ───────────────────────────────────────────────────────────────────

// Path to the built CLI entrypoint.
let cliPath = () => {
  let root = Node.processCwd()
  let dist = Node.pathJoin(root, "dist")
  let cli = Node.pathJoin(dist, "cli")
  Node.pathJoin(cli, "index.js")
}

// Spawn CLI via execSync and return stdout.
// Throws if the process exits non-zero — caught by test framework as test failure.
let runCli = (args: array<string>): string => {
  let cli = cliPath()
  let argsStr = Js.Array.joinWith(" ", args)
  // Build: node "<cliPath>" arg1 arg2 ...
  let cmd = `node "${cli}" ${argsStr}`
  Node.execSync(cmd, { encoding: "utf-8", timeout: 30_000, stdio: "pipe" })
}

// ── Tests ─────────────────────────────────────────────────────────────────────
// All three tests use --help / -h / --list which exit 0.
// execSync throws on non-zero exit; the RescriptTest.test() wrapper catches
// unhandled exceptions and marks the test as failed — so exit-code checks are
// implicit via no-throw.

test("CLI --help exits 0 and prints usage information", () => {
  let stdout = runCli(["--help"])
  // exit code 0 is implicit: execSync would throw on non-zero
  let hasUsage = String.includes(stdout, "Usage:") || String.includes(stdout, "--help") || String.includes(stdout, "--list")
  assertion(
    ~message="CLI --help stdout should contain usage patterns",
    (a, b) => a == b,
    hasUsage,
    true,
  )
  assertion(
    ~message="CLI --help stdout should not be empty",
    (a, b) => a > b,
    String.length(stdout),
    0,
  )
})

test("CLI -h (short flag) exits 0 and prints usage information", () => {
  let stdout = runCli(["-h"])
  // exit code 0 is implicit: execSync would throw on non-zero
  let hasUsage = String.includes(stdout, "Usage:") || String.includes(stdout, "--help") || String.includes(stdout, "--list")
  assertion(
    ~message="CLI -h stdout should contain usage patterns",
    (a, b) => a == b,
    hasUsage,
    true,
  )
})

test("CLI --list exits 0 and produces non-empty output", () => {
  let stdout = runCli(["--list"])
  // exit code 0 is implicit: execSync would throw on non-zero
  assertion(
    ~message="CLI --list stdout should not be empty",
    (a, b) => a > b,
    String.length(stdout),
    0,
  )
})

let () = runTests()
