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
@module("node:path") external pathJoin: (string, string) => string = "join"
@val external processEnvGet: string => option<string> = "process.env.__lookupGetter__"

@val external globalFetch: (string, 'init) => promise<'response> = "fetch"
@new external makeAbortController: unit => 'controller = "AbortController"
@get external abortControllerSignal: 'controller => 'signal = "signal"
@send external abortControllerAbort: 'controller => unit = "abort"
@get external responseStatus: 'response => int = "status"
@send external responseJson: 'response => promise<JSON.t> = "json"

@module("node:fs") external readFileSync: string => string = "readFileSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
@module("node:fs") external existsSync: string => bool = "existsSync"

@val external setTimeoutMs: (unit => unit, float) => float = "setTimeout"
@val external clearTimeoutId: float => unit = "clearTimeout"
@val external consoleWarnStr: string => unit = "console.warn"
