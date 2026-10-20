// src/Providers/Anthropic.res
// Anthropic provider — Claude Code subscription (primary) with admin API fallback.
// Subscription endpoint: https://api.anthropic.com/api/oauth/usage (OAuth access token).
// Admin usage endpoint: https://api.anthropic.com/v1/organizations/{org_id}/usage
// Auth: x-api-key + anthropic-version: 2023-06-01
// orgId resolution: config → auth.json → ANTHROPIC_ORG_ID env.
// Paginated via has_more/next_page cursor, capped at 20 pages.
// 401/403 throws fail-fast (admin scope required).

// --- Constants ----------------------------------------------------------------

let usageUrl = "https://api.anthropic.com/v1/organizations/{org_id}/usage"

// --- Claude Code subscription (OAuth) usage ---------------------------------
// Endpoint: https://api.anthropic.com/api/oauth/usage
// Auth: Authorization: Bearer <access> + anthropic-beta: oauth-2025-04-20.
// Read-only: an expired token is never refreshed here; the user re-runs `claude`.

let oauthUsageUrl = "https://api.anthropic.com/api/oauth/usage"

@new external makeSubscriptionError: string => exn = "Error"

let clampPercent = (value: float): float => value < 0.0 ? 0.0 : value > 100.0 ? 100.0 : value

let dateFromIso = (value: option<JSON.t>): option<Date.t> =>
  switch value {
  | Some(JSON.String(s)) if s !== "" =>
    let ms = Node.jsDateParse(s)
    ms > 0.0 ? Some(Date.fromTime(ms)) : None
  | _ => None
  }

let windowForKind = (kind: string): Domain.windowType =>
  switch kind {
  | "session" => #rolling5h
  | "weekly_all" | "weekly_scoped" => #rollingWeekly
  | _ => #rolling
  }

let limitId = (kind: string, model: option<string>): string =>
  switch (kind, model) {
  | ("session", _) => "anthropic-session"
  | ("weekly_all", _) => "anthropic-weekly"
  | ("weekly_scoped", Some(m)) if m !== "" => `anthropic-weekly-scoped-${m}`
  | ("weekly_scoped", _) => "anthropic-weekly-scoped"
  | ("", _) => "anthropic-usage"
  | (k, _) => `anthropic-${k}`
  }

let subscriptionRow = (
  ~id: string,
  ~kind: string,
  ~percent: float,
  ~reset: option<Date.t>,
  ~model: option<string>,
): Domain.quotaData => {
  let concept = SemanticLabels.anthropicUsageLabel(kind, model)
  {
    id,
    providerName: SemanticLabels.buildProviderName(
      "Anthropic",
      concept.concept,
      ~labelOverride=concept.label,
    ),
    used: clampPercent(percent),
    limit: Some(100.0),
    unit: "%",
    reset,
    window: windowForKind(kind),
    info: Some(concept.label),
    modelId: None,
  }
}

let scopeModel = (value: option<JSON.t>): option<string> =>
  switch value {
  | Some(JSON.Object(scope)) =>
    switch Dict.get(scope, "model") {
    | Some(JSON.Object(model)) =>
      switch Dict.get(model, "display_name") {
      | Some(JSON.String(name)) if name !== "" => Some(name)
      | _ => None
      }
    | _ => None
    }
  | _ => None
  }

// limits[] present (L6 shape): one row per limit entry.
let parseLimits = (entries: array<JSON.t>): array<Domain.quotaData> =>
  entries->Array.filterMap(entry =>
    switch entry {
    | JSON.Object(d) =>
      let kind = switch Dict.get(d, "kind") {
      | Some(JSON.String(k)) => k
      | _ => ""
      }
      switch JsonNum.toNum(Dict.get(d, "percent")->Belt.Option.getWithDefault(JSON.Null)) {
      | Some(percent) =>
        let model = scopeModel(Dict.get(d, "scope"))
        Some(
          subscriptionRow(
            ~id=limitId(kind, model),
            ~kind,
            ~percent,
            ~reset=dateFromIso(Dict.get(d, "resets_at")),
            ~model,
          ),
        )
      | None => None
      }
    | _ => None
    }
  )

// Fallback when limits[] is absent/empty: the five_hour/seven_day windows.
let fallbackSpecs: array<(string, string, string, option<string>)> = [
  ("five_hour", "session", "anthropic-five-hour", None),
  ("seven_day", "weekly_all", "anthropic-seven-day", None),
  ("seven_day_opus", "weekly_scoped", "anthropic-seven-day-opus", Some("Opus")),
  ("seven_day_sonnet", "weekly_scoped", "anthropic-seven-day-sonnet", Some("Sonnet")),
]

let parseFallback = (root: dict<JSON.t>): array<Domain.quotaData> =>
  fallbackSpecs->Array.filterMap(((key, kind, id, model)) =>
    switch Dict.get(root, key) {
    | Some(JSON.Object(window)) =>
      switch JsonNum.toNum(Dict.get(window, "utilization")->Belt.Option.getWithDefault(JSON.Null)) {
      | Some(percent) =>
        Some(
          subscriptionRow(
            ~id,
            ~kind,
            ~percent,
            ~reset=dateFromIso(Dict.get(window, "resets_at")),
            ~model,
          ),
        )
      | None => None
      }
    | _ => None
    }
  )

let parseSubscriptionUsage = (json: JSON.t): array<Domain.quotaData> =>
  switch json {
  | JSON.Object(root) =>
    let limits = switch Dict.get(root, "limits") {
    | Some(JSON.Array(entries)) => parseLimits(entries)
    | _ => []
    }
    Array.length(limits) > 0 ? limits : parseFallback(root)
  | _ => []
  }

let fetchSubscriptionUsage = (
  ~cred: Credential.credential,
  ~http: FetchHttp.httpClient,
): Promise.t<array<Domain.quotaData>> =>
  switch cred {
  | Credential.OAuth(o) if o.expires > 0.0 && Date.now() >= o.expires =>
    Promise.reject(makeSubscriptionError("Claude Code token expired — run `claude` to refresh"))
  | Credential.OAuth(o) =>
    let req: FetchHttp.httpRequest = {
      url: oauthUsageUrl,
      method: #get,
      headers: Some(
        Dict.fromArray([
          ("Authorization", `Bearer ${o.access}`),
          ("anthropic-beta", "oauth-2025-04-20"),
        ]),
      ),
      body: None,
    }
    let opts: FetchHttp.requestOptions = {timeoutMs: 15000.0, retries: 0.0, redact: true}
    http.request(req, opts)->Promise.then(json => Promise.resolve(parseSubscriptionUsage(json)))
  | _ => Promise.resolve([])
  }

// Typed external for admin-usage error with status property.
@new external makeAdminError: string => exn = "Error"

// @get on a JS value to read an HTTP status field.
@get external statusOf: 'a => float = "status"

// Promise.catch wraps rejections as JsExn; unwrap so `status` is visible (R3-001).
let errorStatus = (err: exn): option<float> =>
  JsExn.fromException(err)->Option.flatMap(inner => {
    let status = statusOf(inner)
    status > 0.0 ? Some(status) : None
  })

// Keep the literal HTTP status so isFallthroughError still detects it (R3-001).
let adminDeniedMessage = (status: string): string =>
  `Anthropic admin-usage request denied (HTTP ${status}). Confirm your API key has the Admin API organization usage read permission.`

// --- Helpers -----------------------------------------------------------------



// Maps an Anthropic admin-usage row to a QuotaData entry.
// Token totals (input + output) are summed as the used value.
// Window is inferred from time_bucket granularity (daily for YYYY-MM-DD prefixes).
let mapRow = (row: dict<JSON.t>, idx: int): option<Domain.quotaData> => {
  let usage = switch Dict.get(row, "usage") {
  | Some(JSON.Object(u)) => u
  | _ => Dict.make()
  }
  let inputTokens = JsonNum.toNum(switch Dict.get(usage, "input_tokens") {
  | Some(v) => v
  | _ =>
    switch Dict.get(usage, "prompt_tokens") {
    | Some(v) => v
    | _ => JSON.Number(0.0)
    }
  })
  let outputTokens = JsonNum.toNum(switch Dict.get(usage, "output_tokens") {
  | Some(v) => v
  | _ =>
    switch Dict.get(usage, "completion_tokens") {
    | Some(v) => v
    | _ => JSON.Number(0.0)
    }
  })
  // Helper: check if timeBucket starts with YYYY-MM-DD (daily window)
  let dailyFromTimeBucket = (tb: string): Domain.windowType => {
    let isDaily = tb->String.length >= 10 &&
      tb->String.substring(~start=4, ~end=5) == "-" &&
      tb->String.substring(~start=7, ~end=8) == "-"
    isDaily ? #daily : #rolling
  }
  switch (inputTokens, outputTokens) {
  | (None, None) => None
  | (Some(inp), Some(out)) =>
    let used = inp +. out
    let model = switch Dict.get(row, "model") {
    | Some(JSON.String(m)) => m
    | _ => `row-${Int.toString(idx)}`
    }
    let timeBucket = switch Dict.get(row, "time_bucket") {
    | Some(JSON.String(tb)) => tb
    | _ => ""
    }
    Some({
      id: `anthropic-${model}-${Int.toString(idx)}`,
      providerName: `Anthropic ${model}`,
      used,
      limit: None,
      unit: "tokens",
      reset: None,
      window: dailyFromTimeBucket(timeBucket),
      info: Some(`Anthropic ${model} (${timeBucket})`),
      modelId: None,
    })
  | (Some(inp), None) =>
    let used = inp
    let model = switch Dict.get(row, "model") {
    | Some(JSON.String(m)) => m
    | _ => `row-${Int.toString(idx)}`
    }
    let timeBucket = switch Dict.get(row, "time_bucket") {
    | Some(JSON.String(tb)) => tb
    | _ => ""
    }
    Some({
      id: `anthropic-${model}-${Int.toString(idx)}`,
      providerName: `Anthropic ${model}`,
      used,
      limit: None,
      unit: "tokens",
      reset: None,
      window: dailyFromTimeBucket(timeBucket),
      info: Some(`Anthropic ${model} (${timeBucket})`),
      modelId: None,
    })
  | (None, Some(out)) =>
    let used = out
    let model = switch Dict.get(row, "model") {
    | Some(JSON.String(m)) => m
    | _ => `row-${Int.toString(idx)}`
    }
    let timeBucket = switch Dict.get(row, "time_bucket") {
    | Some(JSON.String(tb)) => tb
    | _ => ""
    }
    Some({
      id: `anthropic-${model}-${Int.toString(idx)}`,
      providerName: `Anthropic ${model}`,
      used,
      limit: None,
      unit: "tokens",
      reset: None,
      window: dailyFromTimeBucket(timeBucket),
      info: Some(`Anthropic ${model} (${timeBucket})`),
      modelId: None,
    })
  }
}

// --- Admin API path (fallback, S5) -------------------------------------------
// Behavior unchanged: needs an API key and an org id resolved from
// config → auth.json → ANTHROPIC_ORG_ID env. 401/403 fails fast with the
// admin-scope hint. Paginated via has_more/next_page.

let extractAdminKey = (cred: Credential.credential): string =>
  switch cred {
  | Credential.Api(c) => c.key
  | Credential.Env(c) =>
    switch Node.processEnv->Dict.get(c.envVar) {
    | Some(v) => v
    | None => ""
    }
  | _ => ""
  }

let fetchAdminUsage = (
  ~key: string,
  ~orgId: string,
  ~http: FetchHttp.httpClient,
): Promise.t<array<Domain.quotaData>> => {
  let baseUrl = String.replace(usageUrl, "{org_id}", orgId)
  let rows: ref<array<Domain.quotaData>> = ref([])
  let rec fetchPage = (nextPage: option<string>): Promise.t<array<Domain.quotaData>> => {
    let pageUrl = switch nextPage {
    | Some(cursor) => `${baseUrl}?page=${cursor}`
    | None => baseUrl
    }
    let req: FetchHttp.httpRequest = {
      url: pageUrl,
      method: #get,
      headers: Some(
        Dict.fromArray([("x-api-key", key), ("anthropic-version", "2023-06-01")]),
      ),
      body: None,
    }
    let opts: FetchHttp.requestOptions = {timeoutMs: 15000.0, retries: 0.0, redact: true}
    http.request(req, opts)
    ->Promise.then(json => {
      switch json {
      | JSON.Object(dict) =>
        let pageData = switch Dict.get(dict, "data") {
        | Some(JSON.Array(arr)) => arr
        | _ => []
        }
        let _ = pageData->Array.forEach(entry => {
          switch entry {
          | JSON.Object(e) =>
            let mapped = mapRow(e, rows.contents->Array.length)
            switch mapped {
            | Some(q) => rows.contents->Array.push(q)->ignore
            | None => ()
            }
          | _ => ()
          }
        })
        let hasMore = switch Dict.get(dict, "has_more") {
        | Some(JSON.Number(n)) => n !== 0.0
        | Some(JSON.String(s)) => s === "true"
        | _ => false
        }
        let nextPage = switch Dict.get(dict, "next_page") {
        | Some(JSON.String(s)) if s !== "" => Some(s)
        | _ => None
        }
        if hasMore && nextPage !== None {
          fetchPage(nextPage)->Promise.then(more => {
            let _ = more->Array.forEach(q => rows.contents->Array.push(q)->ignore)
            Promise.resolve(rows.contents)
          })
        } else {
          Promise.resolve(rows.contents)
        }
      | _ => Promise.resolve(rows.contents)
      }
    })
    ->Promise.catch(. err => {
      // 401/403 = admin scope required — fail-fast with an actionable message
      // that keeps the HTTP status so the resolver can fall through (R3-001).
      switch errorStatus(err) {
      | Some(401.0) => Promise.reject(makeAdminError(adminDeniedMessage("401")))
      | Some(403.0) => Promise.reject(makeAdminError(adminDeniedMessage("403")))
      | _ => Promise.reject(err)
      }
    })
  }
  fetchPage(None)
}

let fetchAdminForCredential = (
  ~cred: Credential.credential,
  ~http: FetchHttp.httpClient,
  ~config: ConfigLoader.quotasConfig,
  ~env: dict<string>,
): Promise.t<array<Domain.quotaData>> => {
  let key = extractAdminKey(cred)
  if key === "" {
    Promise.resolve([])
  } else {
    let orgId = try {
      Infra.resolveAnthropicOrgId(config, ~auth=None, ~env=Some(env), ())
    } catch {
    | _ => ""
    }
    if orgId === "" {
      Promise.resolve([])
    } else {
      fetchAdminUsage(~key, ~orgId, ~http)
    }
  }
}

// --- Provider ----------------------------------------------------------------

// Candidate routing (S4/S5): the Claude Code OAuth candidate uses the
// subscription endpoint; every other candidate keeps the admin org-usage path.
let fetchQuotasForCandidate = (
  ~candidate: CredentialResolver.candidate,
  ~http: FetchHttp.httpClient,
  ~config: ConfigLoader.quotasConfig,
  ~env: dict<string>,
): Promise.t<array<Domain.quotaData>> =>
  switch candidate.origin {
  | #claudeCode => fetchSubscriptionUsage(~cred=candidate.credential, ~http)
  | _ => fetchAdminForCredential(~cred=candidate.credential, ~http, ~config, ~env)
  }

let createAnthropicProvider = (): Provider.quotaProvider => {
  id: "anthropic",
  displayName: "Anthropic",
  category: "subscription",
  authStrategy: #oauth,
  isAvailable: () =>
    CredentialResolver.resolve("anthropic")->Promise.then(opt => {
      Promise.resolve(Belt.Option.isSome(opt))
    }),
  credentialSource: () => CredentialResolver.firstOriginLabel("anthropic"),
  fetchQuotas: () => {
    let http = FetchHttp.make(FetchHttp.noopLogger)
    // A missing/invalid quotas.json only means "no org id override".
    let configPath = Node.pathJoin(Node.pathJoin(Node.processCwd(), ".opencode"), "quotas.json")
    let config = try ConfigLoader.loadConfig(~configPath, ()) catch {
    | _ => ConfigLoader.defaults
    }
    CredentialResolver.resolveEach(~key="anthropic", ~fn=candidate =>
      fetchQuotasForCandidate(~candidate, ~http, ~config, ~env=Node.processEnv)
    )
  },
}

