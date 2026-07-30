// src/Providers/Anthropic.res
// Anthropic provider — env API key variant.
// Admin usage endpoint: https://api.anthropic.com/v1/organizations/{org_id}/usage
// Auth: x-api-key + anthropic-version: 2023-06-01
// orgId resolution: config → auth.json → ANTHROPIC_ORG_ID env.
// Paginated via has_more/next_page cursor, capped at 20 pages.
// 401/403 throws fail-fast (admin scope required).

// --- Constants ----------------------------------------------------------------

let usageUrl = "https://api.anthropic.com/v1/organizations/{org_id}/usage"

// Typed external for admin-usage error with status property.
@new external makeAdminError: string => exn = "Error"

// @get on exn to read the status field from a JS Error object.
@get external errorStatus: exn => float = "status"

// --- Helpers -----------------------------------------------------------------

// Converts any JSON value to option<float>, supporting numeric strings.
let toNum = (json: JSON.t): option<float> => {
  switch json {
  | JSON.Number(n) => Some(n)
  | JSON.String(s) =>
    let trimmed = String.trim(s)
    switch trimmed {
    | "" => None
    | _ =>
      let parsed = Float.fromString(trimmed)
      switch parsed {
      | Some(f) => Some(f)
      | None => None
      }
    }
  | _ => None
  }
}

// Maps an Anthropic admin-usage row to a QuotaData entry.
// Token totals (input + output) are summed as the used value.
// Window is inferred from time_bucket granularity (daily for YYYY-MM-DD prefixes).
let mapRow = (row: dict<JSON.t>, idx: int): option<Domain.quotaData> => {
  let usage = switch Dict.get(row, "usage") {
  | Some(JSON.Object(u)) => u
  | _ => Dict.make()
  }
  let inputTokens = toNum(switch Dict.get(usage, "input_tokens") {
  | Some(v) => v
  | _ =>
    switch Dict.get(usage, "prompt_tokens") {
    | Some(v) => v
    | _ => JSON.Number(0.0)
    }
  })
  let outputTokens = toNum(switch Dict.get(usage, "output_tokens") {
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

// --- Provider ----------------------------------------------------------------

let createAnthropicProvider = (): Provider.quotaProvider => {
  id: "anthropic",
  displayName: "Anthropic",
  category: "api-spend",
  authStrategy: #env,
  isAvailable: () =>
    CredentialResolver.resolve("anthropic")->Promise.then(opt => {
      Promise.resolve(Belt.Option.isSome(opt))
    }),
  fetchQuotas: () => {
    let http = FetchHttp.make(FetchHttp.noopLogger)
    CredentialResolver.resolve("anthropic")->Promise.then(opt => {
      switch opt {
      | None => Promise.resolve([])
      | Some(cred) =>
        // Extract API key from credential
        let key = switch cred {
        | Credential.Api(c) => c.key
        | Credential.Env(c) =>
          switch Node.processEnv->Dict.get(c.envVar) {
          | Some(v) => v
          | None => ""
          }
        | _ => ""
        }
        if key === "" {
          Promise.resolve([])
        } else {
  // Resolve orgId from config → auth.json → env
  let configPath = Node.pathJoin(Node.pathJoin(Node.processCwd(), ".opencode"), "quotas.json")
          let cfg = try {
            Some(ConfigLoader.loadConfig(~configPath, ()))
          } catch {
          | _ => None
          }
          switch cfg {
          | None => Promise.resolve([])
          | Some(c) =>
            let orgId = try {
              Infra.resolveAnthropicOrgId(c, ~auth=None, ~env=Some(Node.processEnv), ())
            } catch {
            | _ => ""
            }
            if orgId === "" {
              Promise.resolve([])
            } else {
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
                  headers: Some(Dict.fromArray([
                    ("x-api-key", key),
                    ("anthropic-version", "2023-06-01"),
                  ])),
                  body: None,
                }
                let opts: FetchHttp.requestOptions = { timeoutMs: 15000.0, retries: 0.0, redact: true }
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
                  // 401/403 = admin scope required — fail-fast with actionable message
                  let status = try {
                    Some(errorStatus(err))
                  } catch {
                  | _ => None
                  }
                  switch status {
                  | Some(401.0) | Some(403.0) =>
                    Promise.reject(
                      makeAdminError("Anthropic admin-usage request denied (401/403). Confirm your API key has the Admin API organization usage read permission.")
                    )
                  | _ => Promise.reject(err)
                  }
                })
              }
              fetchPage(None)
            }
          }
        }
      }
    })
  },
}
