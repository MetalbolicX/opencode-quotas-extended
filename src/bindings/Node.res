@val external processExit: int => unit = "process.exit"

type settlement<'a> = {
  status: [#fulfilled | #rejected],
  value: 'a,
  reason: 'a,
}

@val
external promiseAllSettled: array<promise<'a>> => promise<array<settlement<'a>>> =
  "Promise.allSettled"

// Node built-ins (prefixed to avoid conflicts)
@module("node:os") external osHomedir: unit => string = "homedir"
@module("node:os") external osTmpdir: unit => string = "tmpdir"
@module("node:path") external pathJoin: (string, string) => string = "join"
@val external processEnvGet: string => option<string> = "process.env.__lookupGetter__"

// Read process.env as a plain Dict.t<string>.
@val @scope("process")
external processEnv: Dict.t<string> = "env"

@val external globalFetch: (string, 'init) => promise<'response> = "fetch"
@new external makeAbortController: unit => 'controller = "AbortController"
@get external abortControllerSignal: 'controller => 'signal = "signal"
@send external abortControllerAbort: 'controller => unit = "abort"
@get external responseStatus: 'response => int = "status"
@send external responseJson: 'response => promise<JSON.t> = "json"

@module("node:fs") external readFileSync: string => string = "readFileSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
@module("node:fs") external existsSync: string => bool = "existsSync"
@module("node:fs") external mkdirSync: string => unit = "mkdirSync"
@module("node:fs") external rmSync: string => unit = "rmSync"

type execSyncOpts = {
  encoding: string,
  timeout: int,
  stdio: string,
}

@module("node:child_process")
external execSync: (string, execSyncOpts) => string = "execSync"

@val external setTimeoutMs: (unit => unit, float) => float = "setTimeout"
@val external clearTimeoutId: float => unit = "clearTimeout"
@val external consoleWarnStr: string => unit = "console.warn"

// CLI bindings
@val external processArgv: array<string> = "process.argv"
@module("node:fs") external realpathSync: (string) => string = "realpathSync"
@module("node:url") external fileURLToPath: (string) => string = "fileURLToPath"
@module("node:path") external pathResolve: (string) => string = "resolve"
let processStdoutWrite = (_s: string): bool => %raw("process.stdout.write(_s)")
let processStderrWrite = (_s: string): bool => %raw("process.stderr.write(_s)")
let importMetaUrl = (): string => %raw("import.meta.url")
let processCwd = (): string => %raw("process.cwd()")
