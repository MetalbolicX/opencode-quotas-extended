// src/Providers/Kimi.res
// Kimi / Moonshot provider — subscription usage API.
// Endpoint: https://api.kimi.com/coding/v1/usages

// -----------------------------------------------------------------------------

let usageUrl = "https://api.kimi.com/coding/v1/usages"

// T2.1 — pure request seam for testability (REQ-K-5 s1)
let buildRequest = (authHeader: string): FetchHttp.httpRequest => {
  url: usageUrl,
  method: #get,
  headers: Some(Dict.fromArray([("Authorization", authHeader), ("Accept", "application/json")])),
  body: None,
}

let requestOptions: FetchHttp.requestOptions = { timeoutMs: 15000.0, retries: 0.0, redact: true }

// Extracts Bearer token from Credential.credential
let extractBearerToken = (cred: Credential.credential): string => {
  switch cred {
  | Credential.Api(c) => `Bearer ${c.key}`
  | Credential.OAuth(c) => `Bearer ${c.access}`
  | Credential.Wellknown(c) => `Bearer ${c.token}`
  | Credential.Env(c) =>
    switch Node.processEnv->Dict.get(c.envVar) {
    | Some(v) => v
    | None => ""
    }
  }
}

let createKimiProvider = (): Provider.quotaProvider => {
  id: "kimi",
  displayName: "Kimi / Moonshot",
  category: "coding-plan",
  authStrategy: #oauth,
  isAvailable: () =>
    CredentialResolver.resolve("kimi")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () =>
    CredentialResolver.resolve("kimi")->Promise.then(opt => {
      switch opt {
      | None => Promise.resolve([])
      | Some(cred) =>
        let authHeader = extractBearerToken(cred)
        let http = FetchHttp.make(FetchHttp.noopLogger)
        http.request(buildRequest(authHeader), requestOptions)
        ->Promise.then(json => {
          Promise.resolve(CodingPlanParse.parseKimiUsages(
            ~json,
            ~idPrefix="kimi",
            ~providerName="Kimi / Moonshot"
          ))
        })
      }
    }),
}
