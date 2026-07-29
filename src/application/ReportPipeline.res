// ReportPipeline - simplified version
open Domain

type reportResult = {
  rendered: string,
  errors: dict<string>,
}

type userGroupConfig = {
  strategy: string,
  members: array<string>,
}

type progressBarConfig = {
  width: option<float>,
  filledChar: option<string>,
  emptyChar: option<string>,
  color: option<bool>,
  gradients: option<bool>,
}

type authStrategy = [#api | #oauth | #wellknown | #env]

type credential =
  | Api({variant: string, key: string})
  | OAuth({access: string, refresh: string, expires: float})
  | Wellknown({key: string, token: string})
  | Env({envVar: string})

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<quotaData>>,
}

type credentialSource = {
  get: string => promise<option<credential>>,
}

type historyPoint = {
  timestamp: float,
  used: float,
  limit: option<float>,
}

type historyStore = {
  append: (string, historyPoint) => promise<unit>,
  getHistory: (string, float) => promise<array<historyPoint>>,
  prune: float => promise<unit>,
  resetDetected: (string, historyPoint, float, option<float>) => bool,
}

type httpClientOptions = {
  timeoutMs: float,
  retries: float,
  redact: bool,
}

type httpClient = {
  request: (string, httpClientOptions) => promise<unit>,
}

type logger = {
  debug: (string, unit) => unit,
  info: (string, unit) => unit,
  warn: (string, unit) => unit,
  error: (string, unit) => unit,
}

type translator = {
  t: (string, option<dict<string>>) => string,
}

type renderContext = {
  mode: renderMode,
  color: option<string>,
  compact: option<bool>,
  progressBar: option<progressBarConfig>,
  terminalWidth: option<float>,
  header: option<{brand: string, plan: option<string>}>,
  t: translator,
}

type renderer = {
  render: (array<quotaData>, renderContext) => string,
}

type reportDeps_config = {
  displayMode: renderMode,
  disabled: array<string>,
  aggregatedGroups: dict<userGroupConfig>,
  historyMaxAgeHours: float,
  predictionWindowMinutes: float,
  predictionShortWindowMinutes: float,
  showUnaggregated: bool,
  progressBar: option<progressBarConfig>,
}

type reportDeps = {
  credentialResolver: credentialSource,
  httpClient: httpClient,
  registry: {
    list: unit => array<quotaProvider>,
    get: string => option<quotaProvider>,
  },
  historyStore: historyStore,
  config: reportDeps_config,
  logger: logger,
}

type reportOptions = {
  providerId: option<string>,
  modelId: option<string>,
  mode: renderMode,
  compact: option<bool>,
  color: option<string>,
  now: option<float>,
}

let selectRenderer = Renderers.selectRenderer
let createI18nTranslator = Translator.createI18nTranslator

let reportQuotas = async (deps: reportDeps, opts: reportOptions): promise<reportResult> => {
  let providers = switch opts.providerId {
  | Some(id) => deps.registry.list()->Belt.Array.keep(p => p.id === id)
  | None => deps.registry.list()
  }

  if providers->Belt.Array.length === 0 {
    let errors = Dict.make()
    Dict.set(errors, "_", "No providers found.")
    let rendered = ""
    let result: reportResult = {rendered, errors}
    Promise.resolve(result)
  } else {
    let allData: array<quotaData> = []
    let errors: dict<string> = Dict.make()

    let fetches = providers->Belt.Array.map(p => p.fetchQuotas())
    let results = await Node.promiseAllSettled(fetches)

    for i in 0 to results->Belt.Array.length - 1 {
      let r = results->Belt.Array.getExn(i)
      if r.status === #fulfilled {
        let data: array<quotaData> = r.value
        for j in 0 to data->Belt.Array.length - 1 {
          allData->Belt.Array.push(data->Belt.Array.getExn(j))
        }
      } else {
        let provider = providers->Belt.Array.getExn(i)
        let reason = String.make(r.reason)
        Dict.set(errors, provider.id, reason)
      }
    }

    let now = switch opts.now {
    | Some(n) => n
    | None => Date.now()
    }

    for idx in 0 to allData->Belt.Array.length - 1 {
      let q = allData->Belt.Array.getExn(idx)
      try {
        await deps.historyStore.append(q.id, {timestamp: now, used: q.used, limit: q.limit})
      } catch {
      | _err => ()
      }
    }

    let userGroups: array<Domain.Aggregation.aggregationGroup> = Dict.toArray(
      deps.config.aggregatedGroups,
    )->Belt.Array.map(((groupId, g)) => {
      Domain.Aggregation.makeAggregationGroup(
        ~id=groupId,
        ~providerId="",
        ~strategy=switch g.strategy {
        | "most_critical" => #mostCritical
        | "max" => #max
        | "min" => #min
        | "mean" => #mean
        | "median" => #median
        | _ => #max
        },
      )
    })

    let mergedGroups = mergeAggregationGroups(userGroups, defaultAggregationGroups)

    let displayRows = if mergedGroups->Belt.Array.length === 0 {
      allData->Belt.Array.copy
    } else {
      allData
    }

    let filteredRows = switch opts.modelId {
    | Some(mid) => displayRows->Belt.Array.keep(q => q.id === mid || q.modelId === Some(mid))
    | None => displayRows
    }

    if filteredRows->Belt.Array.length === 0 {
      let rendered = ""
      let result: reportResult = {rendered, errors}
      Promise.resolve(result)
    } else {
      let translator = createI18nTranslator(Translator.enCatalog)
      let renderer = selectRenderer(opts.mode)

      let rendered = renderer.render(
        filteredRows,
        {
          mode: opts.mode,
          color: opts.color,
          compact: opts.compact,
          progressBar: (deps.config.progressBar :> option<Renderers.progressBarConfig>),
          terminalWidth: None,
          header: None,
          t: (translator :> Renderers.translator),
        },
      )

      let result: reportResult = {rendered, errors}
      Promise.resolve(result)
    }
  }
}
