// src/Cli/Cli.res
// CLI entry point — dispatches to list or provider mode.
// Mirrors src/cli/index.ts (TS original retained for rollback).
// Flags: -l/--list -p/--provider -c/--color -m/--mode -h/--help
// Exit: 0 render success, 1 partial/diagnostic, 2 usage error.

open ParseArgs
open JsonFileHistory

// ── Local types ───────────────────────────────────────────────────────────────

// historyPoint is already defined in ReportPipeline — reuse it via local alias
type historyPoint = ReportPipeline.historyPoint

// ── JsonFileHistory deps (Node.js built-ins) ───────────────────────────────────

let historyDeps: JsonFileHistory.deps = {
  readFileSync: Node.readFileSync,
  writeFileSync: Node.writeFileSync,
  existsSync: Node.existsSync,
  now: () => Date.now(),
}

// ── USAGE ──────────────────────────────────────────────────────────────────────

let validColorNames = Colors.validColorNames->Array.join(", ")

let usageText = `opencode-quotas — display AI provider quota usage.

Usage: opencode-quotas [flags]

Flags:
  -l, --list            Show available subscriptions and credential source (default when no flags)
  -p, --provider <id>   Filter to a single provider (e.g. openai, anthropic)
  -c, --color <name>    Color for the usage bar: ${validColorNames}
  -m, --mode <mode>     Output format for list and usage: table (default), json, markdown
  -h, --help            Show this usage information
`

// ── Subscription list (S1/S2/S3) ───────────────────────────────────────────────

// One list row per provider that selects a credential source. The label is the
// first locally selected source — no quota fetch, no token refresh, no network.
let collectListRows = (
  providers: array<Provider.quotaProvider>,
): Promise.t<array<SubscriptionList.row>> => {
  let collected: array<SubscriptionList.row> = []
  let rec next = (index: int): Promise.t<unit> =>
    switch providers->Array.get(index) {
    | None => Promise.resolve()
    | Some(p) =>
      p.credentialSource()
      ->Promise.then(label => {
        switch label {
        | Some(source) =>
          collected->Array.push({id: p.id, name: p.displayName, credential: source})->ignore
        | None => ()
        }
        next(index + 1)
      })
      ->Promise.catch(. _err => next(index + 1))
    }
  next(0)->Promise.then(_ => Promise.resolve(collected))
}

// ── progressBar structural conversion (design §8) ──────────────────────────────
// ConfigLoader.progressBar has all-required fields; ReportPipeline.progressBarConfig
// has all-option fields wrapped in Some. Convert at the CLI boundary.
let convertProgressBar = (pb: ConfigLoader.progressBar): ReportPipeline.progressBarConfig => {
  {
    width: Some(pb.width),
    filledChar: Some(pb.filledChar),
    emptyChar: Some(pb.emptyChar),
    color: Some(pb.color),
    gradients: Some(pb.gradients),
  }
}

// ── Noop history store ───────────────────────────────────────────────────────

// Deprecated: use makeDurableHistory instead for persistent quota history
let _makeNoopHistory = (): ReportPipeline.historyStore => {
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

// ── Durable history store ─────────────────────────────────────────────────────

// Builds a durable JsonFileHistory store that persists to quota-history.json
// flushNow() is called before CLI exit to ensure history is not lost.
let makeDurableHistory = (): JsonFileHistory.store => {
  let historyPath = Paths.getHistoryPath(~env=None)
  JsonFileHistory.make(~debounceMs=5000.0, historyPath, historyDeps)
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

let runList = (args: ParseArgs.parsedArgs): Promise.t<unit> => {
  let reg = Registry.buildDefaultRegistry()
  collectListRows(reg.all())->Promise.then(rows => {
    if rows->Array.length === 0 {
      let msg = Messages.formatNoSubscriptions()
      Node.processStderrWrite(`${msg}\n`)->ignore
      Node.processExit(1)
      Promise.resolve()
    } else {
      let rendered = switch args.mode {
      | #json => SubscriptionList.renderJson(~rows)
      // Table and markdown are the same list by design (S1).
      | #table | #markdown => SubscriptionList.renderMarkdown(~rows)
      }
      // The final newline is emitted exactly once, here at the CLI boundary.
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
  let historyStore = makeDurableHistory()
  // ReportPipeline.httpClient is declared but never used — pass a stub to satisfy the type
  let stubHttp: ReportPipeline.httpClient = {
    request: (_url, _opts) => Promise.resolve()
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
        // REQ-E-3-2: load .opencode/quotas.json via ConfigLoader with defaults fallback
        let configPath = Node.pathJoin(Node.pathJoin(Node.processCwd(), ".opencode"), "quotas.json")
        let cfg = try {
          ConfigLoader.loadConfig(~configPath, ())
        } catch {
        | _ => ConfigLoader.defaults
        }
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
            disabled: cfg.disabled,
            aggregatedGroups: (cfg.aggregatedGroups :> dict<ReportPipeline.userGroupConfig>),
            historyMaxAgeHours: cfg.historyMaxAgeHours,
            predictionWindowMinutes: cfg.predictionWindowMinutes,
            predictionShortWindowMinutes: cfg.predictionShortWindowMinutes,
            showUnaggregated: cfg.showUnaggregated,
            progressBar: Some(convertProgressBar(cfg.progressBar)),
          },
          logger: (logger :> ReportPipeline.logger),
          selectRenderer: (Renderers.selectRenderer :> (Domain.renderMode) => ReportPipeline.renderer),
          createI18nTranslator: (_: unit) => (Translator.createI18nTranslator(Translator.enCatalog) :> ReportPipeline.translator),
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
        // Flush history to disk before exit (durable store)
        historyStore.flushNow()
        // Extract error outputs via pure functions (I/O stays here)
        let providerErr = ReportErrors.formatProviderErrors(result.errors)
        let fatalErr = ReportErrors.formatFatalError(result.errors)
        // Write provider errors to stderr (partial result — exit 0)
        switch providerErr.channel {
        | #stderr => Node.processStderrWrite(providerErr.text)->ignore
        | _ => ()
        }
        // Fatal error → stdout + exit 1; otherwise render output + exit 0
        switch fatalErr.channel {
        | #stdout =>
          Node.processStdoutWrite(fatalErr.text)->ignore
          Node.processExit(fatalErr.exitCode)
        | #none | #stderr =>
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
