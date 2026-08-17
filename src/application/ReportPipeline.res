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

// Alias the port type — this is the canonical provider type used throughout the pipeline.
type quotaProvider = Provider.quotaProvider

type credentialSource = {
  get: string => promise<option<credential>>,
}

// Alias Domain's canonical historyPoint (Types.res:46)
type historyPoint = Domain.historyPoint

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
  selectRenderer: (renderMode) => renderer,
  createI18nTranslator: (unit) => translator,
}

type reportOptions = {
  providerId: option<string>,
  modelId: option<string>,
  mode: renderMode,
  compact: option<bool>,
  color: option<string>,
  now: option<float>,
}

// ── Application-layer group type (not the domain aggregationGroup) ─────────────────
// Used to carry explicit member ids for user groups and providerId for defaults.

type pipelineGroup = {
  id: string,
  strategy: aggregationStrategy,
  memberIds: option<array<string>>,
  providerId: string,
}

// ── buildEttlMap ───────────────────────────────────────────────────────────────
// Computes estimated-time-to-limit per quota from history.
// Eligibility: limit == Some(l) && Float.isFinite(l) && l > 0.0
// Only FINITE ETTL values are inserted into the map.
// Cold start (<2 usable points): no map entry.
// Read failure: warn + skip, quota row still renders.

let buildEttlMap = async (
  store: historyStore,
  now: float,
  quotas: array<quotaData>,
  cfg: reportDeps_config,
  log: logger,
) => {
  let result: dict<float> = Dict.make()
  let historyWindowMs = cfg.historyMaxAgeHours *. 3.6e6 > cfg.predictionWindowMinutes *. 6e4
    ? cfg.historyMaxAgeHours *. 3.6e6
    : cfg.predictionWindowMinutes *. 6e4

  for idx in 0 to quotas->Belt.Array.length - 1 {
    let q = quotas->Belt.Array.getExn(idx)
    let eligible = switch q.limit {
      | Some(l) => Float.isFinite(l) && l > 0.0
      | None => false
    }
    if eligible {
      let history = await (
        store.getHistory(q.id, historyWindowMs)
        ->Promise.catch(. _exn => {
          log.warn(`[ETTL] getHistory failed for ${q.id}`, ())
          Promise.resolve([])
        })
      )
      if history->Belt.Array.length >= 2 {
        let ettl = Prediction.predictTimeToLimit(
          history,
          ~params={
            windowMinutes: Some(cfg.predictionWindowMinutes),
            shortWindowMinutes: Some(cfg.predictionShortWindowMinutes),
            now: Some(now),
            windowInfo: q.info,
          },
        )
        if Float.isFinite(ettl) {
          let _ = Dict.set(result, q.id, ettl)
        }
      }
    }
  }
  result
}

// ── displayRows ─────────────────────────────────────────────────────────────────
// When user has configured aggregatedGroups: render aggregated group rows.
// When no groups configured: render flat allData (byte-identical to current behavior).

let displayRows = (
  allData: array<quotaData>,
  userGroups: array<pipelineGroup>,
  defaultGroups: array<Aggregation.aggregationGroup>,
  mergedGroups: array<Aggregation.aggregationGroup>,
  ettlMap: dict<float>,
  showUnaggregated: bool,
): array<quotaData> => {
  // Activation: user has configured at least one group
  let hasUserGroups = userGroups->Belt.Array.length > 0
  if !hasUserGroups {
    // No user groups → flat output, byte-identical to current behavior
    allData->Belt.Array.copy
  } else {
    // Build effective groups: user groups with explicit members,
    // defaults matched by providerId-prefix (q.id === providerId || startsWith(providerId + "-"))
    let effectiveGroups: array<(Aggregation.aggregationGroup, array<quotaData>)> = []

    // User groups: use explicit memberIds
    for uIdx in 0 to userGroups->Belt.Array.length - 1 {
      let ug = userGroups->Belt.Array.getExn(uIdx)
      let memberIds = switch ug.memberIds {
      | Some(ids) => ids
      | None => []
      }
      let members = allData->Belt.Array.keep(q =>
        memberIds->Belt.Array.getBy(id => id === q.id)->Option.isSome
      )
      let aggGroup: Aggregation.aggregationGroup = {
        id: ug.id,
        providerId: ug.providerId,
        strategy: ug.strategy,
      }
      let _ = effectiveGroups->Belt.Array.push((aggGroup, members))
    }

    // Default groups: match via providerId-prefix
    for dIdx in 0 to defaultGroups->Belt.Array.length - 1 {
      let dg = defaultGroups->Belt.Array.getExn(dIdx)
      let members = allData->Belt.Array.keep(q =>
        q.id === dg.providerId || String.startsWith(q.id, dg.providerId ++ "-")
      )
      let _ = effectiveGroups->Belt.Array.push((dg, members))
    }

    // Aggregate each group
    let aggregated: array<quotaData> = []
    for gIdx in 0 to effectiveGroups->Belt.Array.length - 1 {
      let (group, members) = effectiveGroups->Belt.Array.getExn(gIdx)
      if members->Belt.Array.length > 0 {
        switch Aggregation.aggregate(members, group.strategy, ~ettlMap) {
        | Some(row) =>
          let _ = aggregated->Belt.Array.push(row)
        | None => ()
        }
      }
    }

    // Optionally add ungrouped rows
    if showUnaggregated {
      let groupedIds = effectiveGroups->Belt.Array.map(((_, ms)) => ms->Belt.Array.map(q => q.id))
      let allGroupedIds = groupedIds->Belt.Array.reduce([], (acc, ids) => acc->Belt.Array.concat(ids))
      let ungrouped = allData->Belt.Array.keep(q =>
        allGroupedIds->Belt.Array.getBy(id => id === q.id)->Option.isNone
      )
      aggregated->Belt.Array.concat(ungrouped)
    } else {
      aggregated
    }
  }
}

// ── reportQuotas ───────────────────────────────────────────────────────────────

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

    // Append loop: record current usage
    for idx in 0 to allData->Belt.Array.length - 1 {
      let q = allData->Belt.Array.getExn(idx)
      try {
        await deps.historyStore.append(q.id, {timestamp: now, used: q.used, limit: q.limit})
      } catch {
      | _err => ()
      }
    }

    // Build ETTL map AFTER append (current sample included in history)
    let ettlMap = await buildEttlMap(deps.historyStore, now, allData, deps.config, deps.logger)

    // Prune old history after reads
    try {
      await deps.historyStore.prune(deps.config.historyMaxAgeHours *. 3.6e6)
    } catch {
    | _exn => ()
    }

    // Build pipeline groups from user config
    let userGroups: array<pipelineGroup> = Dict.toArray(
      deps.config.aggregatedGroups,
    )->Belt.Array.map(((groupId, g)) => {
      {
        id: groupId,
        strategy: switch g.strategy {
        | "most_critical" => #mostCritical
        | "max" => #max
        | "min" => #min
        | "mean" => #mean
        | "median" => #median
        | _ => #max
        },
        memberIds: Some(g.members),
        providerId: "",
      }
    })

    let mergedGroups = Aggregation.mergeAggregationGroups(
      userGroups->Belt.Array.map(ug => {
        DomainFixtures.makeAggregationGroup(~id=ug.id, ~providerId=ug.providerId, ~strategy=ug.strategy)
      }),
      AggregationDefaults.defaultAggregationGroups,
    )

    let rows = displayRows(
      allData,
      userGroups,
      AggregationDefaults.defaultAggregationGroups,
      mergedGroups,
      ettlMap,
      deps.config.showUnaggregated,
    )

    let filteredRows = switch opts.modelId {
    | Some(mid) => rows->Belt.Array.keep(q => q.id === mid || q.modelId === Some(mid))
    | None => rows
    }

    if filteredRows->Belt.Array.length === 0 {
      let rendered = ""
      let result: reportResult = {rendered, errors}
      Promise.resolve(result)
    } else {
      let translator = deps.createI18nTranslator(())
      let renderer = deps.selectRenderer(opts.mode)

      let rendered = renderer.render(
        filteredRows,
        {
          mode: opts.mode,
          color: opts.color,
          compact: opts.compact,
          progressBar: deps.config.progressBar,
          terminalWidth: None,
          header: None,
          t: translator,
        },
      )

      let result: reportResult = {rendered, errors}
      Promise.resolve(result)
    }
  }
}
