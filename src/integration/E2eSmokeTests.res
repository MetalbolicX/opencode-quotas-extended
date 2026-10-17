// src/integration/E2eSmokeTests.res
// End-to-end CLI contract: spawns the bundled CLI at dist/cli/index.js.
//
// Covers the list redesign (S1/S2/S3/S5) with exact stdout/stderr/exit checks
// plus the surface-level smoke cases (help, unknown flag) ported from the old
// vitest integration suites.
//
// Every child process runs in a fully isolated home:
//   * XDG_DATA_HOME, PI_CODING_AGENT_DIR, CLAUDE_CONFIG_DIR, HOME → temp dir
//   * PATH → an empty dir inside that home (no mmx binary, no live session)
//   * provider API env vars set to empty, so no inherited key can leak in
// The child writes to files under the temp home, which is removed before the
// assertions run, so cleanup happens even when a run throws. No real credential
// file is read and no network request is made.
//
// Requires `pnpm build` first (the bundle is what these tests execute).
open RescriptTest

autoBoot := false

// ── Child process helpers ────────────────────────────────────────────────────

let cliPath = (): string => {
  let root = Node.processCwd()
  Node.pathJoin(Node.pathJoin(Node.pathJoin(root, "dist"), "cli"), "index.js")
}

let readFileUtf8 = (path: string): string =>
  Node.readFileSyncUtf8(path, {encoding: "utf8"})

// Absolute node path captured before PATH is narrowed for the child, so the
// isolated PATH never has to resolve `node`.
let nodePath = (): string =>
  String.trim(Node.execSync("command -v node", {encoding: "utf8", timeout: 10_000, stdio: "pipe"}))

type cliResult = {
  stdout: string,
  stderr: string,
  exitCode: int,
}

// Runs the bundled CLI with output captured to files. `echo $?` keeps the
// shell's own status at 0, so execSync never throws on an expected non-zero exit.
let runIsolated = (~home: string, args: array<string>): cliResult => {
  let outFile = Node.pathJoin(home, "stdout.txt")
  let errFile = Node.pathJoin(home, "stderr.txt")
  let codeFile = Node.pathJoin(home, "code.txt")
  let argsStr = Js.Array.joinWith(" ", args)
  let env =
    `HOME="${home}" USERPROFILE="${home}" ` ++
    `XDG_DATA_HOME="${home}" PI_CODING_AGENT_DIR="${home}/pi" CLAUDE_CONFIG_DIR="${home}/claude" ` ++
    `PATH="${home}/bin" ` ++
    `OPENAI_API_KEY= ANTHROPIC_API_KEY= GEMINI_API_KEY= KIMI_API_KEY= MINIMAX_API_KEY= ANTHROPIC_ORG_ID=`
  let cmd =
    `${env} ${nodePath()} "${cliPath()}" ${argsStr} > "${outFile}" 2> "${errFile}"; echo $? > "${codeFile}"`
  let _ = Node.execSync(cmd, {encoding: "utf-8", timeout: 30_000, stdio: "pipe"})
  {
    stdout: readFileUtf8(outFile),
    stderr: readFileUtf8(errFile),
    exitCode: Belt.Int.fromString(String.trim(readFileUtf8(codeFile)))->Belt.Option.getWithDefault(-1),
  }
}

// Runs and cleans up in one step: the temp home is always removed, even when
// the CLI throws.
let runCase = (~home: string, args: array<string>): cliResult => {
  let result = try {
    runIsolated(~home, args)
  } catch {
  | _exn => {stdout: "", stderr: "", exitCode: -1}
  }
  Node.rmSyncRecursive(home, {force: true, recursive: true})
  result
}

// ── Isolated homes ───────────────────────────────────────────────────────────

let homeCounter = ref(0)

let makeHome = (~authJson: option<string>): string => {
  homeCounter := homeCounter.contents + 1
  let home =
    Node.osTmpdir() ++
    "/e2e-list-" ++
    String.make(Date.now()) ++
    "-" ++
    Int.toString(homeCounter.contents)
  let ensure = (path: string): unit =>
    try {
      let _ = Node.mkdirSync(path)
    } catch {
    | _ => ()
    }
  ensure(home)
  ensure(home ++ "/opencode")
  ensure(home ++ "/pi")
  ensure(home ++ "/claude")
  // Empty bin dir: the child's narrowed PATH resolves nothing, so Minimax's
  // `which mmx` probe can never reach a real CLI or a live session.
  ensure(home ++ "/bin")
  switch authJson {
  | Some(content) => {
      let _ = Node.writeFileSync(home ++ "/opencode/auth.json", content)
    }
  | None => ()
  }
  home
}

// Two subscriptions only: openai and zai, both from opencode's auth.json.
let twoProviderAuthJson = JSON.stringify(
  JSON.Object(
    Dict.fromArray([
      ("openai", JSON.Object(Dict.fromArray([
        ("type", JSON.String("api")),
        ("key", JSON.String("fixture-openai-key")),
      ]))),
      ("zai-coding-plan", JSON.Object(Dict.fromArray([
        ("type", JSON.String("api")),
        ("key", JSON.String("fixture-zai-key")),
      ]))),
    ]),
  ),
)

let footer = "Run `opencode-quotas -p <id>` to see usage for one subscription."

let expectedTwoRowTable = [
  "## Available subscriptions (2)",
  "",
  "| # | ID     | Provider         | Credential |",
  "|--:|--------|------------------|------------|",
  "| 1 | openai | OpenAI           | opencode   |",
  "| 2 | zai    | z.ai Coding Plan | opencode   |",
  "",
  footer,
]->Array.join("\n") ++ "\n"

let expectedTwoRowJson = [
  "[",
  "  {",
  "    \"id\": \"openai\",",
  "    \"name\": \"OpenAI\",",
  "    \"credential\": \"opencode\"",
  "  },",
  "  {",
  "    \"id\": \"zai\",",
  "    \"name\": \"z.ai Coding Plan\",",
  "    \"credential\": \"opencode\"",
  "  }",
  "]",
]->Array.join("\n") ++ "\n"

// ── Assertions ───────────────────────────────────────────────────────────────

let assertExact = (
  ~label: string,
  ~expectedStdout: string,
  ~expectedStderr: string,
  ~expectedExit: int,
  result: cliResult,
): unit => {
  assertion(~message=`${label}: exit code`, (a, b) => a == b, result.exitCode, expectedExit)
  assertion(
    ~message=`${label}: stdout must match exactly, got:\n${result.stdout}`,
    (a, b) => a == b,
    result.stdout,
    expectedStdout,
  )
  assertion(
    ~message=`${label}: stderr must match exactly, got:\n${result.stderr}`,
    (a, b) => a == b,
    result.stderr,
    expectedStderr,
  )
}

let assertTable = (~label: string, result: cliResult): unit =>
  assertExact(
    ~label,
    ~expectedStdout=expectedTwoRowTable,
    ~expectedStderr="",
    ~expectedExit=0,
    result,
  )

// ── S1: table and markdown are identical ─────────────────────────────────────

test("S1: `-l -m table` prints the exact subscription table", () => {
  let result = runCase(~home=makeHome(~authJson=Some(twoProviderAuthJson)), ["-l", "-m", "table"])
  assertTable(~label="-l -m table", result)
})

test("S1: `-l -m markdown` is byte-identical to table mode", () => {
  let result = runCase(
    ~home=makeHome(~authJson=Some(twoProviderAuthJson)),
    ["-l", "-m", "markdown"],
  )
  assertTable(~label="-l -m markdown", result)
})

test("S1: list is the default with no flags", () => {
  let result = runCase(~home=makeHome(~authJson=Some(twoProviderAuthJson)), [])
  assertTable(~label="no flags", result)
})

test("S5: `--list` (long flag) behaves like `-l`", () => {
  let result = runCase(~home=makeHome(~authJson=Some(twoProviderAuthJson)), ["--list"])
  assertTable(~label="--list", result)
})

// ── S3: JSON mode ────────────────────────────────────────────────────────────

test("S3: `-l -m json` prints only the id/name/credential array", () => {
  let result = runCase(
    ~home=makeHome(~authJson=Some(twoProviderAuthJson)),
    ["-l", "-m", "json"],
  )
  assertExact(
    ~label="-l -m json",
    ~expectedStdout=expectedTwoRowJson,
    ~expectedStderr="",
    ~expectedExit=0,
    result,
  )
})

// ── S5: preserved error contracts ────────────────────────────────────────────

test("S5: missing auth.json keeps its diagnostic and exits 1", () => {
  let home = makeHome(~authJson=None)
  let expectedStderr = [
    "No OpenCode subscription file found.",
    `Checked: ${home}/opencode/auth.json`,
    "",
    "Add API keys via:",
    "  opencode auth login",
    "  Or set OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY / MINIMAX_API_KEY / KIMI_API_KEY",
  ]->Array.join("\n") ++ "\n"
  let result = runCase(~home, ["-l"])
  assertExact(
    ~label="missing auth.json",
    ~expectedStdout="",
    ~expectedStderr,
    ~expectedExit=1,
    result,
  )
})

test("S5: an auth.json with no usable credential reports no subscriptions, exit 1", () => {
  let expectedStderr = [
    "No subscriptions with credentials found.",
    "",
    "Configured providers need API keys. Run 'opencode-quotas -l' after adding keys.",
  ]->Array.join("\n") ++ "\n"
  let result = runCase(~home=makeHome(~authJson=Some("{}")), ["-l"])
  assertExact(
    ~label="no subscriptions",
    ~expectedStdout="",
    ~expectedStderr,
    ~expectedExit=1,
    result,
  )
})

test("S5: `-l -p <id>` is a usage error with the existing message", () => {
  let result = runCase(
    ~home=makeHome(~authJson=Some(twoProviderAuthJson)),
    ["-l", "-p", "openai"],
  )
  assertExact(
    ~label="-l with -p",
    ~expectedStdout="",
    ~expectedStderr=`Cannot combine -l/--list with -p/--provider\n${Cli.usageText}\n`,
    ~expectedExit=2,
    result,
  )
})

// ── S5: previous behavior of the provider flow ───────────────────────────────

test("S5: `-p <id>` without a credential keeps its previous diagnostic", () => {
  let expectedFor = (id: string): string =>
    `No credentials found for '${id}'.\n\nAvailable: openai, go, zai, kimi, minimax, anthropic, gemini\n`
  let check = (id: string): unit => {
    let result = runCase(~home=makeHome(~authJson=Some("{}")), ["-p", id])
    assertExact(
      ~label=`-p ${id} without credential`,
      ~expectedStdout="",
      ~expectedStderr=expectedFor(id),
      ~expectedExit=1,
      result,
    )
  }
  check("openai")
  check("zai")
})

// ── Smoke: help and flag errors ──────────────────────────────────────────────

test("CLI --help exits 0 and prints usage", () => {
  let result = runCase(~home=makeHome(~authJson=None), ["--help"])
  assertExact(
    ~label="--help",
    ~expectedStdout=`${Cli.usageText}\n`,
    ~expectedStderr="",
    ~expectedExit=0,
    result,
  )
})

test("CLI -h (short flag) exits 0 and prints usage", () => {
  let result = runCase(~home=makeHome(~authJson=None), ["-h"])
  assertExact(
    ~label="-h",
    ~expectedStdout=`${Cli.usageText}\n`,
    ~expectedStderr="",
    ~expectedExit=0,
    result,
  )
})

test("CLI unknown flag exits 2 with the usage text on stderr", () => {
  let result = runCase(~home=makeHome(~authJson=None), ["--unknown-flag"])
  assertion(~message="unknown flag exits 2", (a, b) => a == b, result.exitCode, 2)
  assertion(~message="unknown flag writes nothing to stdout", (a, b) => a == b, result.stdout, "")
  assertion(
    ~message="unknown flag stderr carries the usage text",
    (a, b) => a == b,
    String.includes(result.stderr, Cli.usageText),
    true,
  )
})

test("CLI `-m json --help` prints help, exit 0", () => {
  let result = runCase(~home=makeHome(~authJson=None), ["-m", "json", "--help"])
  assertExact(
    ~label="-m json --help",
    ~expectedStdout=`${Cli.usageText}\n`,
    ~expectedStderr="",
    ~expectedExit=0,
    result,
  )
})

let () = runTests()
