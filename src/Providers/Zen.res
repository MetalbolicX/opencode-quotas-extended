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
    ProviderFetch.fetch(
      ~key="opencode",
      ~buildUrl=() => usageUrl,
      ~parse=json => CodingPlanParse.parseUsage(
        ~json,
        ~idPrefix="zen",
        ~providerName="Zen",
      ),
      ~http=FetchHttp.make(FetchHttp.noopLogger),
      ~_logger=FetchHttp.noopLogger,
    ),
}
