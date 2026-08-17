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
    ProviderFetch.fetch(
      ~key="opencode-go",
      ~buildUrl=() => usageUrl,
      ~parse=json => CodingPlanParse.parseUsage(
        ~json,
        ~idPrefix="go",
        ~providerName="Go",
      ),
      ~http=FetchHttp.make(FetchHttp.noopLogger),
      ~_logger=FetchHttp.noopLogger,
    ),
}
