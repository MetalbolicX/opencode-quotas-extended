// src/Providers/Zen.res
// opencode Zen provider — api variant.
// Endpoint: https://opencode.ai/api/billing/balance

// -----------------------------------------------------------------------------

let usageUrl = "https://opencode.ai/api/billing/balance"

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
        let authHeader = BearerToken.extract(cred)
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
