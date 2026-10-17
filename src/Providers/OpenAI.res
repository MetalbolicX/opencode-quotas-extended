// src/Providers/OpenAI.res
// OpenAI provider — supports oauth (ChatGPT Plus/Pro) and api/platform key variants.
// OAuth: /backend-api/wham/usage (rate_limit + credits)
// API:   /v1/usage with cursor-based pagination.

open SemanticLabels

// --- Helpers -----------------------------------------------------------------

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

type oauthRefreshHooks = {
  reread: unit => option<Credential.credential>,
  persist: (string, string, float) => bool,
}

type refreshedOAuth = {access: string, refresh: string, expires: float}

let refreshInFlight: ref<option<Promise.t<option<refreshedOAuth>>>> = ref(None)

let refreshOAuth = (
  ~cred: refreshedOAuth,
  ~http: FetchHttp.httpClient,
  ~hooks: oauthRefreshHooks,
): Promise.t<option<refreshedOAuth>> => {
  switch refreshInFlight.contents {
  | Some(promise) => promise
  | None =>
    let req: FetchHttp.httpRequest = {
      url: TokenRefresh.tokenUrl,
      method: #post,
      headers: Some(Dict.fromArray([("Content-Type", "application/x-www-form-urlencoded")])),
      body: Some(JSON.String(TokenRefresh.refreshRequestBody(cred.refresh))),
    }
    let opts: FetchHttp.requestOptions = {timeoutMs: 15000.0, retries: 0.0, redact: true}
    let promise = http.request(req, opts)->Promise.then(json => {
      let parsed = TokenRefresh.parseRefreshResponse(JSON.stringify(json))
      switch parsed {
      | None => Promise.resolve(None)
      | Some(tokens) =>
        let refresh = Belt.Option.getWithDefault(tokens.refresh, cred.refresh)
        let expires = Date.now() +. tokens.expiresInSeconds *. 1000.0
        try {
          let _ = hooks.persist(tokens.access, refresh, expires)
        } catch {
        | _ => ()
        }
        Promise.resolve(Some({access: tokens.access, refresh, expires}))
      }
    })->Promise.catch(. _err => Promise.resolve(None))
    refreshInFlight := Some(promise)
    let _ = promise->Promise.then(_ => {
      refreshInFlight := None
      Promise.resolve()
    })
    promise
  }
}

let fetchWhamWithAccess = (
  ~access: string,
  ~http: FetchHttp.httpClient,
): Promise.t<array<Domain.quotaData>> => {
  let auth = `Bearer ${access}`
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
            let used = JsonNum.toNum(switch Dict.get(w, "used_percent") {
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
                  JsonNum.toNum(switch Dict.get(w, "reset_after_seconds") { | Some(v) => v | _ => JSON.Number(0.0) }),
                  JsonNum.toNum(switch Dict.get(w, "reset_at") { | Some(v) => v | _ => JSON.Number(0.0) }),
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
            switch JsonNum.toNum(bal) {
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
}

let fetchQuotasOAuthWithHooks = (
  ~cred: Credential.credential,
  ~http: FetchHttp.httpClient,
  ~hooks: oauthRefreshHooks,
): Promise.t<array<Domain.quotaData>> => {
  switch cred {
  | Credential.OAuth(initial) =>
    let initialRefreshed = ref(false)
    let initialOAuth: refreshedOAuth = {access: initial.access, refresh: initial.refresh, expires: initial.expires}
    let proactively = TokenRefresh.needsRefresh(initial.expires, Date.now()) && initial.refresh !== ""
    let ready = if proactively {
      refreshOAuth(~cred=initialOAuth, ~http, ~hooks)->Promise.then(result => {
        switch result {
        | Some(tokens) =>
          initialRefreshed := true
          Promise.resolve(tokens)
        | None => Promise.resolve(initialOAuth)
        }
      })
    } else {
      Promise.resolve(initialOAuth)
    }
    ready->Promise.then(used => {
      fetchWhamWithAccess(~access=used.access, ~http)->Promise.catch(. err => {
        let message = switch JsExn.anyToExnInternal(err) {
        | JsExn(v) => Belt.Option.getWithDefault(JsExn.message(v), String.make(v))
        | e => String.make(e)
        }
        let message = message ++ " " ++ String.make(err)
        if String.includes(message, "HTTP 401") {
          switch hooks.reread() {
          | Some(Credential.OAuth(latest)) if latest.access !== used.access =>
            fetchWhamWithAccess(~access=latest.access, ~http)
          | Some(Credential.OAuth(latest)) if !initialRefreshed.contents && latest.refresh !== "" =>
            let refreshCred: refreshedOAuth = {access: latest.access, refresh: latest.refresh, expires: latest.expires}
            refreshOAuth(~cred=refreshCred, ~http, ~hooks)->Promise.then(result =>
              switch result {
              | Some(tokens) =>
                initialRefreshed := true
                fetchWhamWithAccess(~access=tokens.access, ~http)
              | None => Promise.reject(err)
              }
            )
          | _ if !initialRefreshed.contents && used.refresh !== "" =>
            let refreshCred: refreshedOAuth = {access: used.access, refresh: used.refresh, expires: used.expires}
            refreshOAuth(~cred=refreshCred, ~http, ~hooks)->Promise.then(result =>
              switch result {
              | Some(tokens) =>
                initialRefreshed := true
                fetchWhamWithAccess(~access=tokens.access, ~http)
              | None => Promise.reject(err)
              }
            )
          | _ => Promise.reject(err)
          }
        } else {
          Promise.reject(err)
        }
      })
    })
  | _ => Promise.resolve([])
  }
}

let defaultOAuthRefreshHooks: oauthRefreshHooks = {
  reread: () => AuthJsonSource.getCredential("openai"),
  persist: (access, refresh, expiresMs) =>
    AuthJsonSource.persistOAuthTokens(~env=None, "openai", access, refresh, expiresMs),
}

@new external makeError: string => exn = "Error"

// pi rotates and locks its own auth.json, so a pi token is used as-is: never
// refreshed, never written back. Expired → reject with the resolver's fallthrough
// hint so the next candidate (or a "run pi" message) takes over.
let fetchQuotasOAuthReadOnly = (
  ~cred: Credential.credential,
  ~http: FetchHttp.httpClient,
  ~harness: string,
): Promise.t<array<Domain.quotaData>> =>
  switch cred {
  | Credential.OAuth(o) if o.expires > 0.0 && Date.now() >= o.expires =>
    Promise.reject(makeError(`OpenAI token from ${harness} ${CredentialResolver.expiredHint} \`${harness}\` to refresh`))
  | Credential.OAuth(o) => fetchWhamWithAccess(~access=o.access, ~http)
  | _ => Promise.resolve([])
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
                let used = JsonNum.toNum(switch Dict.get(e, "generated") { | Some(v) => v | _ => JSON.Number(0.0) })
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
                  let limitUser = JsonNum.toNum(switch Dict.get(dict, "limit_user") { | Some(v) => v | _ => JSON.Number(0.0) })
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
    // Note: HTTP/network failures reject and propagate up to ReportPipeline.
    // Only "no credential" (handled by isAvailable gate above) returns [].
  }
  fetchPage(None)
}

// --- Provider ----------------------------------------------------------------

// Refresh write-back only ever targets the file the token came from: opencode's.
let fetchQuotasForCandidate = (
  ~candidate: CredentialResolver.candidate,
  ~http: FetchHttp.httpClient,
  ~hooks: oauthRefreshHooks,
): Promise.t<array<Domain.quotaData>> =>
  switch (candidate.credential, candidate.origin) {
  | (Credential.OAuth(_) as cred, #opencode) => fetchQuotasOAuthWithHooks(~cred, ~http, ~hooks)
  | (Credential.OAuth(_) as cred, #pi) => fetchQuotasOAuthReadOnly(~cred, ~http, ~harness="pi")
  | (Credential.OAuth(_) as cred, _) => fetchQuotasOAuthReadOnly(~cred, ~http, ~harness="its harness")
  | (cred, _) => fetchQuotasApiKey(~cred, ~http)
  }

let createOpenAIProvider = (): Provider.quotaProvider => {
  id: "openai",
  displayName: "OpenAI",
  category: "subscription",
  authStrategy: #oauth,
  isAvailable: () =>
    CredentialResolver.resolve("openai")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  credentialSource: () => CredentialResolver.firstOriginLabel("openai"),
  fetchQuotas: () => {
    let http = FetchHttp.make(FetchHttp.noopLogger)
    CredentialResolver.resolveEach(~key="openai", ~fn=candidate =>
      fetchQuotasForCandidate(~candidate, ~http, ~hooks=defaultOAuthRefreshHooks)
    )
  },
}
