// Node.js bindings - all externals used across the codebase.

@val external processExit: int => unit = "process.exit"

@val external jsDateParse: string => float = "Date.parse"

type settlement<'a> = {
  status: [#fulfilled | #rejected],
  value: 'a,
  reason: exn,
}

@val external promiseAllSettled: array<promise<'a>> => promise<array<settlement<'a>>> = "Promise.allSettled"

@module("node:os") external osHomedir: unit => string = "homedir"
@module("node:os") external osTmpdir: unit => string = "tmpdir"
@module("node:path") external pathJoin: (string, string) => string = "join"
@val external processEnvGet: string => option<string> = "process.env.__lookupGetter__"

@val @scope("process") external processEnv: Dict.t<string> = "env"

@val external globalFetch: (string, 'init) => promise<'response> = "fetch"
@new external makeAbortController: unit => 'controller = "AbortController"
@get external abortControllerSignal: 'controller => 'signal = "signal"
@send external abortControllerAbort: 'controller => unit = "abort"
@get external responseStatus: 'response => int = "status"
@send external responseJson: 'response => promise<JSON.t> = "json"

@module("node:fs") external readFileSync: string => string = "readFileSync"
// Overload: read with explicit UTF-8 encoding so result is always string.
type readFileSyncUtf8Opts = { encoding: string }
@module("node:fs")
external readFileSyncUtf8: (string, readFileSyncUtf8Opts) => string = "readFileSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
@module("node:fs") external existsSync: string => bool = "existsSync"
@module("node:fs") external mkdirSync: string => unit = "mkdirSync"
@module("node:fs") external rmSync: string => unit = "rmSync"

type dirEnt = {
  name: string,
  isDirectory: unit => bool,
  isFile: unit => bool,
}

type readdirSyncOpts = { withFileTypes: bool }

@module("node:fs")
external readdirSync: (string, readdirSyncOpts) => array<dirEnt> = "readdirSync"

@module("node:fs") external statSync: string => dirEnt = "statSync"

type execSyncOpts = {
  encoding: string,
  timeout: int,
  stdio: string,
}

@module("node:child_process") external execSync: (string, execSyncOpts) => string = "execSync"

@module("node:child_process") external execSyncSimple: string => string = "execSync"

type spawnSyncOpts = {
  encoding: string,
  stdio: string,
}

type spawnSyncResult = {
  status: option<int>,
  signal: option<string>,
  output: array<string>,
  pid: int,
}

@module("node:child_process") external spawnSync: (string, spawnSyncOpts) => spawnSyncResult = "spawnSync"

@val external setTimeoutMs: (unit => unit, float) => float = "setTimeout"
@val external clearTimeoutId: float => unit = "clearTimeout"
@val external consoleWarnStr: string => unit = "console.warn"

@val external processArgv: array<string> = "process.argv"
@module("node:fs") external realpathSync: string => string = "realpathSync"
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"
@module("node:path") external pathResolve: string => string = "resolve"
@val external processStdoutWrite: string => bool = "process.stdout.write"
@val external processStderrWrite: string => bool = "process.stderr.write"
@val external processCwd: unit => string = "process.cwd"

@val @scope("process") external processChdir: string => unit = "chdir"
@val external importMetaUrl: string = "import.meta.url"
