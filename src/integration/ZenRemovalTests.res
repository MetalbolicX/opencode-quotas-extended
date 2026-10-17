// src/integration/ZenRemovalTests.res
// T1 (S4/S5): isolated CLI contract for the removed Zen provider.
// Spawns the built CLI at dist/cli/index.js with `-p zen` and asserts:
//   * exit code 1 (unknown provider)
//   * empty stdout
//   * exact stderr diagnostic listing the 7 remaining providers
//
// All credential-bearing env vars (XDG_DATA_HOME, PI_CODING_AGENT_DIR,
// CLAUDE_CONFIG_DIR) are redirected under os.tmpdir() for the child process
// only; the test creates a dummy opencode auth.json, never reads real
// credentials, and performs no network I/O. The temp home is removed after the
// outputs are captured so teardown always runs.
open RescriptTest

autoBoot := false

// ── helpers ───────────────────────────────────────────────────────────────────

let cliPath = (): string => {
  let root = Node.processCwd()
  Node.pathJoin(Node.pathJoin(Node.pathJoin(root, "dist"), "cli"), "index.js")
}

let readFileUtf8 = (path: string): string =>
  Node.readFileSyncUtf8(path, {encoding: "utf8"})

type cliResult = {
  stdout: string,
  stderr: string,
  exitCode: int,
}

// Runs the built CLI in a child shell with isolated credential env vars and
// file-redirected output. Returns the exact captured stdout/stderr/exit code.
// The trailing `echo $? > codeFile` keeps the shell's own exit code at 0, so
// execSync never throws on the CLI's expected non-zero exit.
let runIsolated = (~home: string, args: array<string>): cliResult => {
  let outFile = Node.pathJoin(home, "stdout.txt")
  let errFile = Node.pathJoin(home, "stderr.txt")
  let codeFile = Node.pathJoin(home, "code.txt")
  let argsStr = Js.Array.joinWith(" ", args)
  let cmd =
    `XDG_DATA_HOME="${home}" PI_CODING_AGENT_DIR="${home}/pi" CLAUDE_CONFIG_DIR="${home}/claude" ` ++
    `node "${cliPath()}" ${argsStr} > "${outFile}" 2> "${errFile}"; echo $? > "${codeFile}"`
  let _ = Node.execSync(cmd, {encoding: "utf-8", timeout: 30_000, stdio: "pipe"})
  {
    stdout: readFileUtf8(outFile),
    stderr: readFileUtf8(errFile),
    exitCode: Belt.Int.fromString(String.trim(readFileUtf8(codeFile)))->Belt.Option.getWithDefault(-1),
  }
}

// Creates an isolated temp home with a valid (dummy) opencode auth.json so the
// unknown-provider path is exercised without touching real credential files.
let makeHome = (): string => {
  let home = Node.osTmpdir() ++ "/zenremoval-" ++ String.make(Date.now())
  let _ = Node.mkdirSync(home)
  let _ = Node.mkdirSync(Node.pathJoin(home, "opencode"))
  let _ = Node.mkdirSync(Node.pathJoin(home, "pi"))
  let _ = Node.mkdirSync(Node.pathJoin(home, "claude"))
  let authJson = "{\"opencode\":{\"type\":\"api\",\"key\":\"dummy-zen-removal-key\"}}"
  let _ = Node.writeFileSync(Node.pathJoin(Node.pathJoin(home, "opencode"), "auth.json"), authJson)
  home
}

let cleanup = (home: string): unit =>
  Node.rmSyncRecursive(home, {recursive: true, force: true})

// ── Tests ─────────────────────────────────────────────────────────────────────

test("T1/S4: `-p zen` reports unknown provider, exact stderr, empty stdout, exit 1", () => {
  let home = makeHome()
  let result: cliResult = try {
    runIsolated(~home, ["-p", "zen"])
  } catch {
  | _exn => {stdout: "", stderr: "", exitCode: -1}
  }
  cleanup(home)
  let expectedStderr =
    "No credentials found for 'zen'.\n\n" ++
    "Available: openai, go, zai, kimi, minimax, anthropic, gemini\n"
  assertion(~message="exit code must be 1", (a, b) => a == b, result.exitCode, 1)
  assertion(
    ~message=`stdout must be empty, got: ${result.stdout}`,
    (a, b) => a == b,
    result.stdout,
    "",
  )
  assertion(
    ~message=`stderr must match exactly, got:\n${result.stderr}`,
    (a, b) => a == b,
    result.stderr,
    expectedStderr,
  )
})

let () = runTests()
