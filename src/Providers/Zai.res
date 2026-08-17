// src/Providers/Zai.res
// z.ai Coding Plan provider — oauth variant.
// Endpoint: https://api.z.ai/api/monitor/usage/quota/limit

// -----------------------------------------------------------------------------

let usageUrl = "https://api.z.ai/api/monitor/usage/quota/limit"

let createZaiProvider = (): Provider.quotaProvider => {
  id: "zai",
  displayName: "z.ai Coding Plan",
  category: "coding-plan",
  authStrategy: #oauth,
  isAvailable: () =>
    CredentialResolver.resolve("zai-coding-plan")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () =>
    CredentialResolver.resolve("zai-coding-plan")->Promise.then(opt => {
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
          Promise.resolve(CodingPlanParse.parseZaiLimits(
            ~json,
            ~idPrefix="zai",
            ~providerName="z.ai",
          ))
        })
      }
    }),
}
