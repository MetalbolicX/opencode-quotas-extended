// src/Cli/Cli.res
// CLI entry point — dispatches to list or provider mode.
// Mirrors src/cli/index.ts (TS original retained for rollback).
// Flags: -l/--list -p/--provider -c/--color -m/--mode -h/--help
// Exit: 0 render success, 1 partial/diagnostic, 2 usage error.

open ParseArgs

// ── Local types ───────────────────────────────────────────────────────────────

// historyPoint is already defined in ReportPipeline — reuse it via local alias
type historyPoint = ReportPipeline.historyPoint

// ── USAGE ──────────────────────────────────────────────────────────────────────

let validColorNames = Colors.validColorNames->Array.join(", ")

let usageText = `opencode-quotas — display AI provider quota usage.

Usage: opencode-quotas [flags]

Flags:
  -l, --list            Show available providers as a numbered list (default when no flags)
  -p, --provider <id>   Filter to a single provider (e.g. openai, anthropic)
  -c, --color <name>    Color for the usage bar: ${validColorNames}
  -m, --mode <mode>     Output format: table (default), json, markdown
  -h, --help            Show this usage information
`

// ── List table renderer ────────────────────────────────────────────────────────

let renderListTable = (providers: array<Provider.quotaProvider>): string => {
  let rows = providers->Array.mapWithIndex((p, idx) => {
    let num = Int.toString(idx + 1)
    [num, p.id, p.displayName, "—", "—", "available"]->Array.join("  ")
  })
  let header = ["#", "id", "displayName", "status", "percent", "availability"]->Array.join("  ")
  [header, ...rows]->Array.join("\n")
}

// ── Noop history store ───────────────────────────────────────────────────────

let makeNoopHistory = (): ReportPipeline.historyStore => {
  let append = (_id: string, _point: historyPoint): Promise.t<unit> => Promise.resolve()
  let getHistory = (_id: string, _ms: float): Promise.t<array<historyPoint>> => Promise.resolve([])
  let prune = (_ms: float): Promise.t<unit> => Promise.resolve()
  let resetDetected = (
    _id: string,
    _prev: historyPoint,
    _used: float,
    _limit: option<float>,
  ): bool => false
  {append, getHistory, prune, resetDetected}
}

// ── Noop logger ───────────────────────────────────────────────────────────────

// ReportPipeline.logger uses (string, unit) => unit — different from FetchHttp.logger
let makeReportPipelineLogger = (): ReportPipeline.logger => {
  let debug = (_msg: string, (_: unit)) => ()
  let info = (_msg: string, (_: unit)) => ()
  let warn = (_msg: string, (_: unit)) => ()
  let error = (_msg: string, (_: unit)) => ()
  {debug, info, warn, error}
}

// ── Filter helpers (local inline to avoid Filter type nominal mismatch) ───────

// Filters providers that successfully return true on isAvailable.
// Isolates provider failures — one bad provider doesn't kill the list.
let filterAvailableProvidersInline = (
  providers: array<Provider.quotaProvider>,
): Promise.t<array<Provider.quotaProvider>> => {
  let collected: array<Provider.quotaProvider> = []
  let pushIfAvail = (p: Provider.quotaProvider, isAvail: bool): Promise.t<unit> => {
    if isAvail {
      collected->Array.push(p)->ignore
    }
    Promise.resolve()
  }
  let chain: Promise.t<unit> = Promise.resolve()
  let finalChain = providers->Array.reduce(chain, (acc, p) => {
    (acc->Promise.then(_ =>
      p.isAvailable()
      ->Promise.then(isAvail => pushIfAvail(p, isAvail))
      ->Promise.catch(. _err => pushIfAvail(p, false))
    ): Promise.t<unit>)
  })
  finalChain->Promise.then(_ => Promise.resolve(collected))
}

// ── Pipeline runner ─────────────────────────────────────────────────────────────

// Wrapper that calls reportQuotas and returns the raw result.
let runPipeline = async (
  deps: ReportPipeline.reportDeps,
  opts: ReportPipeline.reportOptions,
): Promise.t<ReportPipeline.reportResult> => {
  await ReportPipeline.reportQuotas(deps, opts)
}

// ── Dispatch helpers ─────────────────────────────────────────────────────────

let printHelp = (): unit => {
  Node.processStdoutWrite(usageText)->ignore
}

let runList = (_args: ParseArgs.parsedArgs): Promise.t<unit> => {
  let reg = Registry.buildDefaultRegistry()
  let all = reg.all()
  filterAvailableProvidersInline(all)
  ->Promise.then(avail => {
    if avail->Array.length === 0 {
      let msg = Messages.formatNoSubscriptions()
      Node.processStderrWrite(`${msg}\n`)->ignore
      Node.processExit(1)
      Promise.resolve()
    } else {
      let rendered = renderListTable(avail)
      Node.processStdoutWrite(`${rendered}\n`)->ignore
      Node.processExit(0)
      Promise.resolve()
    }
  })
  ->Promise.catch(. _err => {
    Node.processStderrWrite("Error rendering list\n")->ignore
    Node.processExit(1)
    Promise.resolve()
  })
}

let runProviderFlow = async (providerId: string, args: ParseArgs.parsedArgs): unit => {
  let reg = Registry.buildDefaultRegistry()
  let logger = makeReportPipelineLogger()
  let historyStore = makeNoopHistory()
  // ReportPipeline.httpClient is declared but never used — pass a stub to satisfy the type
  let stubHttp: ReportPipeline.httpClient = {
    request: (_url, _opts) => Promise.resolve(%raw("undefined"))
  }

  // REQ-CRED-3: check provider is registered
  let provider = reg.get(providerId)
  switch provider {
  | None =>
    let msg = Messages.formatNoCredentialsForProvider(providerId, reg.ids())
    Node.processStderrWrite(`${msg}\n`)->ignore
    Node.processExit(1)
  | Some(p) => {
      let isAvail = await p.isAvailable()
      if !isAvail {
        let msg = Messages.formatNoCredentialsForProvider(providerId, reg.ids())
        Node.processStderrWrite(`${msg}\n`)->ignore
        Node.processExit(1)
      } else {
        // REQ-PP-1..5: run the full pipeline
        let deps: ReportPipeline.reportDeps = {
          credentialResolver: {
            get: (_id: string) => Promise.resolve(None)
          },
          httpClient: stubHttp,
          registry: {
            list: () => reg.all(),
            get: (id: string) => reg.get(id),
          },
          historyStore: (historyStore :> ReportPipeline.historyStore),
          config: {
            displayMode: args.mode,
            disabled: [],
            aggregatedGroups: Dict.make(),
            historyMaxAgeHours: 24.0,
            predictionWindowMinutes: 60.0,
            predictionShortWindowMinutes: 5.0,
            showUnaggregated: false,
            progressBar: None,
          },
          logger: (logger :> ReportPipeline.logger),
        }
        let opts: ReportPipeline.reportOptions = {
          providerId: Some(providerId),
          modelId: None,
          mode: args.mode,
          compact: None,
          color: args.color,
          now: Some(Date.now()),
        }
        // runPipeline is async -> returns Promise.t<X>, calling it is Promise.t<Promise.t<X>>
        // so await await to fully unwrap
        let result = await await runPipeline(deps, opts)
        // WU-6 option B: partial-result provider errors to stderr, exit 0
        let allKeys = result.errors->Dict.keysToArray
        let errorKeys = allKeys->Belt.Array.keep(k => k !== "_")
        if errorKeys->Array.length > 0 {
          // Build error dict for formatProviderFetchErrors
          let errorDict: dict<string> = Dict.make()
          let _ = errorKeys->Array.map(key => {
            let msg = switch result.errors->Dict.get(key) {
            | Some(m) => m
            | None => ""
            }
            let _ = Dict.set(errorDict, key, msg)
          })
          Node.processStderrWrite(`${Messages.formatProviderFetchErrors(errorDict)}\n`)->ignore
        }
        switch result.errors->Dict.get("_") {
        | Some(msg) =>
          Node.processStdoutWrite(`${msg}\n`)->ignore
          Node.processExit(1)
        | None =>
          Node.processStdoutWrite(`${result.rendered}\n`)->ignore
          Node.processExit(0)
        }
      }
    }
  }
}

let dispatch = (args: ParseArgs.parsedArgs): Promise.t<unit> => {
  if args.help {
    printHelp()
    Node.processExit(0)
    Promise.resolve()
  } else if args.provider !== None {
    runProviderFlow(Belt.Option.getExn(args.provider), args)
  } else {
    // REQ-CRED-1: check auth.json before list
    let authPath = Paths.getAuthJsonPath(~env=None)
    if !Node.existsSync(authPath) {
      Node.processStderrWrite(`${Messages.formatMissingAuthJson(authPath)}\n`)->ignore
      Node.processExit(1)
      Promise.resolve()
    } else {
      runList(args)
    }
  }
}

// ── run — testable entry point ─────────────────────────────────────────────────

type runResult = {
  stdout: string,
  stderr: string,
  exitCode: int,
}

let run = async (argv: array<string>): runResult => {
  let stdout: ref<string> = ref("")
  let stderr: ref<string> = ref("")
  let exitCode: ref<int> = ref(0)

  switch ParseArgs.parse(argv) {
  | Error(msg) =>
    let errMsg = `${msg}\n${usageText}\n`
    stderr := errMsg
    Node.processStderrWrite(errMsg)->ignore
    exitCode := 2
  | Ok(args) =>
    if args.help {
      stdout := usageText
      Node.processStdoutWrite(`${usageText}\n`)->ignore
      exitCode := 0
    } else {
      await dispatch(args)
    }
  }

  {stdout: stdout.contents, stderr: stderr.contents, exitCode: exitCode.contents}
}

// ── main — CLI bootstrap ────────────────────────────────────────────────────────

let main = async (argv: array<string>): unit => {
  // Slice off [node, scriptPath] to get the user-facing args
  let result = await run(argv->Belt.Array.sliceToEnd(2))
  Node.processExit(result.exitCode)
}
