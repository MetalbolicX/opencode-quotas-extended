// src/Providers/Go.res
// opencode Go provider — api variant.
// Endpoint: https://opencode.ai/api/billing/balance

// -----------------------------------------------------------------------------

let usageUrl = "https://opencode.ai/api/billing/balance"

let createGoProvider = (): Provider.quotaProvider => {
  id: "go",
  displayName: "opencode Go",
  category: "coding-plan",
  authStrategy: #api,
  isAvailable: () =>
    CredentialResolver.resolve("opencode-go")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () =>
    CredentialResolver.resolveOrEmpty(~key="opencode-go", ~fn=cred => {
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
          ~idPrefix="go",
          ~providerName="Go"
        ))
      })
    }),
}
