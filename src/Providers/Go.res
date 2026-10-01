// src/Providers/Go.res
// opencode Go provider — official subscription usage API (no scraping).
// Endpoint: https://opencode.ai/zen/go/v1/usage

// -----------------------------------------------------------------------------

let usageUrl = "https://opencode.ai/zen/go/v1/usage"

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
    ProviderFetch.fetch(
      ~key="opencode-go",
      ~buildUrl=() => usageUrl,
      ~parse=json => CodingPlanParse.parseGoUsage(
        ~json,
        ~idPrefix="go",
        ~providerName="Go",
      ),
      ~http=FetchHttp.make(FetchHttp.noopLogger),
      ~_logger=FetchHttp.noopLogger,
    ),
}
