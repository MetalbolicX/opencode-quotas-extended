// src/Providers/Kimi.res
// Kimi / Moonshot provider.
// Endpoint: https://api.moonshot.cn/api/usage/quota (placeholder — no public quota API).

// --- Local type declarations (mirrors port interfaces) -----------------------

type authStrategy = [#api | #oauth | #wellknown | #env]

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<QuotaData.quotaData>>,
}

// -----------------------------------------------------------------------------

let usageUrl = "https://api.moonshot.cn/api/usage/quota"

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

let createKimiProvider = (): quotaProvider => {
  id: "kimi",
  displayName: "Kimi / Moonshot",
  category: "coding-plan",
  authStrategy: #oauth,
  isAvailable: () =>
    CredentialResolver.resolve("kimi-for-coding")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () =>
    CredentialResolver.resolve("kimi-for-coding")->Promise.then(opt => {
      switch opt {
      | None => Promise.resolve([])
      | Some(cred) =>
        let authHeader = extractBearerToken(cred)
        let http = FetchHttp.make(FetchHttp.noopLogger)
        let req: FetchHttp.httpRequest = {
          url: usageUrl,
          method: #get,
          headers: Some(Dict.fromArray([("Authorization", authHeader)])),
          body: None,
        }
        let opts: FetchHttp.requestOptions = { timeoutMs: 15000.0, retries: 0.0, redact: true }
        http.request(req, opts)
        ->Promise.then(json => {
          Promise.resolve(CodingPlanParse.parseMonitorLimits(
            ~json,
            ~idPrefix="kimi",
            ~providerName="Kimi"
          ))
        })
      }
    }),
}
