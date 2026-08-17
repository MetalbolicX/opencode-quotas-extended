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
    ProviderFetch.fetch(
      ~key="zai-coding-plan",
      ~buildUrl=() => usageUrl,
      ~parse=json => CodingPlanParse.parseZaiLimits(
        ~json,
        ~idPrefix="zai",
        ~providerName="z.ai",
      ),
      ~http=FetchHttp.make(FetchHttp.noopLogger),
      ~_logger=FetchHttp.noopLogger,
    ),
}
