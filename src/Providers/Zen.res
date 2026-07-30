// src/Providers/Zen.res
// opencode Zen provider — api variant.
// Endpoint: https://opencode.ai/api/billing/balance

// -----------------------------------------------------------------------------

let usageUrl = "https://opencode.ai/api/billing/balance"

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

let createZenProvider = (): Provider.quotaProvider => {
  id: "zen",
  displayName: "opencode Zen",
  category: "coding-plan",
  authStrategy: #api,
  isAvailable: () =>
    CredentialResolver.resolve("opencode")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () =>
    CredentialResolver.resolve("opencode")->Promise.then(opt => {
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
          Promise.resolve(CodingPlanParse.parseUsage(
            ~json,
            ~idPrefix="zen",
            ~providerName="Zen"
          ))
        })
      }
    }),
}
