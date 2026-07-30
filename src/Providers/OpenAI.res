// src/Providers/OpenAI.res
// OpenAI provider — supports oauth (ChatGPT Plus/Pro) and api/platform key variants.
// OAuth: /backend-api/wham/usage (rate_limit + credits)
// API:   /v1/usage with cursor-based pagination.

open SemanticLabels

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
      | None =>
        let withoutPct = switch trimmed->String.endsWith("%") {
        | true => trimmed->String.slice(~start=-1)->String.trim
        | false => trimmed
        }
        Float.fromString(withoutPct)
      }
    }
  | _ => None
  }
}

// Builds reset Date from reset_after_seconds or reset_at epoch.
let resetDate = (afterSeconds: option<float>, atEpoch: option<float>): option<Date.t> => {
  switch atEpoch {
  | Some(ts) => Some(Date.fromTime(ts *. 1000.0))
  | None =>
    switch afterSeconds {
    | Some(secs) =>
      let resetMs = Date.now() +. (secs *. 1000.0)
      Some(Date.fromTime(resetMs))
    | None => None
    }
  }
}

// --- OAuth path: fetch from WHAM ----------------------------------------------

let whamUrl = "https://chatgpt.com/backend-api/wham/usage"

let fetchQuotasOAuth = (
  ~cred: Credential.credential,
  ~http: FetchHttp.httpClient,
): Promise.t<array<Domain.quotaData>> => {
  // Build auth header from credential
  let auth = switch cred {
  | Credential.Api(c) => `Bearer ${c.key}`
  | Credential.OAuth(c) => `Bearer ${c.access}`
  | Credential.Wellknown(c) => `Bearer ${c.token}`
  | Credential.Env(c) =>
    switch Node.processEnv->Dict.get(c.envVar) {
    | Some(v) => v
    | None => ""
    }
  }
  // Wrap client with Authorization header
  let authedClient: FetchHttp.httpClient = {
    request: (req: FetchHttp.httpRequest, opts) => {
      let newHeaders = switch req.headers {
      | Some(h) =>
        let copy = Dict.copy(h)
        let _ = Dict.set(copy, "Authorization", auth)
        Some(copy)
      | None =>
        let d = Dict.make()
        let _ = Dict.set(d, "Authorization", auth)
        Some(d)
      }
      let authedReq: FetchHttp.httpRequest = { url: req.url, method: req.method, headers: newHeaders, body: req.body }
      http.request(authedReq, opts)
    },
  }
  let req: FetchHttp.httpRequest = {
    url: whamUrl,
    method: #get,
    headers: None,
    body: None,
  }
  let opts: FetchHttp.requestOptions = { timeoutMs: 15000.0, retries: 0.0, redact: true }
  authedClient.request(req, opts)
  ->Promise.then(json => {
    // Parse json: { rate_limit: { primary_window: {...}, secondary_window: {...} }, credits: {...} }
    let quotaData: array<Domain.quotaData> = []
    switch json {
    | JSON.Object(dict) =>
      // Primary + secondary windows
      let primaryConcept = enrichQuotaLabel("openai", {
        type_: None,
        unit: None,
        number: None,
        modelName: None,
        weekly: None,
        openaiVariant: Some("primary"),
        geminiModel: None,
      })
      let secondaryConcept = enrichQuotaLabel("openai", {
        type_: None,
        unit: None,
        number: None,
        modelName: None,
        weekly: None,
        openaiVariant: Some("secondary"),
        geminiModel: None,
      })
      let windows = [
        (primaryConcept, "primary_window", #daily),
        (secondaryConcept, "secondary_window", #rolling),
      ]
      let _ = windows->Array.forEach(((concept, key, win)) => {
        switch Dict.get(dict, "rate_limit") {
        | Some(JSON.Object(rl)) =>
          switch Dict.get(rl, key) {
          | Some(JSON.Object(w)) =>
            let used = toNum(switch Dict.get(w, "used_percent") {
            | Some(v) => v
            | _ => JSON.Number(0.0)
            })
            switch used {
            | Some(u) =>
              let id = key === "primary_window" ? "openai-primary" : "openai-secondary"
              let entry: Domain.quotaData = {
                id,
                providerName: buildProviderName("OpenAI", concept.concept),
                used: u < 0.0 ? 0.0 : u > 100.0 ? 100.0 : u,
                limit: Some(100.0),
                unit: "%",
                reset: resetDate(
                  toNum(switch Dict.get(w, "reset_after_seconds") { | Some(v) => v | _ => JSON.Number(0.0) }),
                  toNum(switch Dict.get(w, "reset_at") { | Some(v) => v | _ => JSON.Number(0.0) }),
                ),
                window: win,
                info: Some(concept.label),
                modelId: None,
              }
              Belt.Array.push(quotaData, entry)->ignore
            | None => ()
            }
          | _ => ()
          }
        | _ => ()
        }
      })
      // Credits
      switch Dict.get(dict, "credits") {
      | Some(JSON.Object(cDict)) =>
        switch Dict.get(cDict, "unlimited") {
        | Some(_) =>
          let concept = enrichQuotaLabel("openai", {
            type_: None,
            unit: None,
            number: None,
            modelName: None,
            weekly: None,
            openaiVariant: Some("credits"),
            geminiModel: None,
          })
          let entry: Domain.quotaData = {
            id: "openai-credits",
            providerName: buildProviderName("OpenAI", concept.concept),
            used: 0.0,
            limit: None,
            unit: "credits",
            reset: None,
            window: #rolling,
            info: Some(concept.label),
            modelId: None,
          }
          Belt.Array.push(quotaData, entry)->ignore
        | None =>
          switch Dict.get(cDict, "balance") {
          | Some(bal) =>
            switch toNum(bal) {
            | Some(b) =>
              let concept = enrichQuotaLabel("openai", {
                type_: None,
                unit: None,
                number: None,
                modelName: None,
                weekly: None,
                openaiVariant: Some("credits"),
                geminiModel: None,
              })
              let entry: Domain.quotaData = {
                id: "openai-credits",
                providerName: buildProviderName("OpenAI", concept.concept),
                used: b,
                limit: None,
                unit: "credits",
                reset: None,
                window: #rolling,
                info: Some(concept.label),
                modelId: None,
              }
              Belt.Array.push(quotaData, entry)->ignore
            | None => ()
            }
          | None => ()
          }
        }
      | _ => ()
      }
    | _ => ()
    }
    Promise.resolve(quotaData)
  })
  ->Promise.catch(. _err => {
    Promise.resolve([])
  })
}

// --- API key path: cursor-based pagination ------------------------------------

let platformUrl = "https://api.openai.com/v1/usage"

let fetchQuotasApiKey = (
  ~cred: Credential.credential,
  ~http: FetchHttp.httpClient,
): Promise.t<array<Domain.quotaData>> => {
  // Extract key
  let key = switch cred {
  | Credential.Api(c) => c.key
  | Credential.Wellknown(c) => c.key
  | Credential.Env(c) =>
    switch Node.processEnv->Dict.get(c.envVar) {
    | Some(v) => v
    | None => ""
    }
  | Credential.OAuth(_) => ""
  }
  let seenIds: ref<array<string>> = ref([])
  let allEntries: array<Domain.quotaData> = []
  let rec fetchPage = (cursor: option<string>): Promise.t<array<Domain.quotaData>> => {
    let builtUrl = switch cursor {
    | Some(c) => `${platformUrl}?page=${c}`
    | None => platformUrl
    }
    let req: FetchHttp.httpRequest = {
      url: builtUrl,
      method: #get,
      headers: Some(Dict.fromArray([("Authorization", `Bearer ${key}`)])),
      body: None,
    }
    let opts: FetchHttp.requestOptions = { timeoutMs: 15000.0, retries: 0.0, redact: true }
    http.request(req, opts)
    ->Promise.then(json => {
      let entries: array<Domain.quotaData> = []
      switch json {
      | JSON.Object(dict) =>
        switch Dict.get(dict, "data") {
        | Some(JSON.Array(dataArr)) =>
          let _ = dataArr->Array.forEach(entry => {
            switch entry {
            | JSON.Object(e) =>
              let idStr = switch Dict.get(e, "id") {
              | Some(JSON.String(s)) => s
              | _ => ""
              }
              if idStr !== "" && !Belt.Array.some(seenIds.contents, id => id === idStr) {
                seenIds.contents->Array.push(idStr)->ignore
                let used = toNum(switch Dict.get(e, "generated") { | Some(v) => v | _ => JSON.Number(0.0) })
                switch used {
                | Some(u) =>
                  let model = switch Dict.get(e, "model") {
                  | Some(JSON.String(m)) => m
                  | _ => "openai-api"
                  }
                  let concept = enrichQuotaLabel("openai", {
                    type_: None,
                    unit: None,
                    number: None,
                    modelName: None,
                    weekly: None,
                    openaiVariant: Some("api"),
                    geminiModel: None,
                  })
                  let limitUser = toNum(switch Dict.get(dict, "limit_user") { | Some(v) => v | _ => JSON.Number(0.0) })
                  let entry: Domain.quotaData = {
                    id: `openai-api-${idStr}`,
                    providerName: buildProviderName("OpenAI", concept.concept),
                    used: u,
                    limit: limitUser,
                    unit: "tokens",
                    reset: None,
                    window: #rolling,
                    info: Some(concept.label),
                    modelId: Some(model),
                  }
                  Belt.Array.push(entries, entry)->ignore
                | None => ()
                }
              }
            | _ => ()
            }
          })
        | _ => ()
        }
        // Determine next page cursor
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
          // Continue pagination
          fetchPage(nextPage)->Promise.then(moreEntries => {
            let _ = moreEntries->Array.forEach(e => Belt.Array.push(allEntries, e)->ignore)
            Promise.resolve(allEntries)
          })
        } else {
          Promise.resolve(allEntries->Belt.Array.concat(entries))
        }
      | _ => Promise.resolve(allEntries->Belt.Array.concat(entries))
      }
    })
    ->Promise.catch(. _err => {
      if allEntries->Array.length > 0 {
        Promise.resolve(allEntries)
      } else {
        Promise.resolve([])
      }
    })
  }
  fetchPage(None)
}

// --- Provider ----------------------------------------------------------------

let createOpenAIProvider = (): Provider.quotaProvider => {
  id: "openai",
  displayName: "OpenAI",
  category: "subscription",
  authStrategy: #oauth,
  isAvailable: () =>
    CredentialResolver.resolve("openai")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () => {
    let http = FetchHttp.make(FetchHttp.noopLogger)
    CredentialResolver.resolve("openai")->Promise.then(opt => {
      switch opt {
      | None => Promise.resolve([])
      | Some(cred) =>
        switch cred {
        | Credential.OAuth(_) =>
          fetchQuotasOAuth(~cred, ~http)
        | _ =>
          fetchQuotasApiKey(~cred, ~http)
        }
      }
    })
  },
}
