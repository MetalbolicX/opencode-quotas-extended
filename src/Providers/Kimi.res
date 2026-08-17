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
    ProviderFetch.fetch(
      ~key="kimi",
      ~buildUrl=() => usageUrl,
      ~parse=json => CodingPlanParse.parseKimiUsages(
        ~json,
        ~idPrefix="kimi",
        ~providerName="Kimi / Moonshot",
      ),
      ~http=FetchHttp.make(FetchHttp.noopLogger),
      ~_logger=FetchHttp.noopLogger,
    ),
}
