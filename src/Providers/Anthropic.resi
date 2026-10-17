// Anthropic provider interface — cross-module surface.
let createAnthropicProvider: unit => Provider.quotaProvider
let oauthUsageUrl: string
let parseSubscriptionUsage: JSON.t => array<Domain.quotaData>
let fetchQuotasForCandidate: (
  ~candidate: CredentialResolver.candidate,
  ~http: FetchHttp.httpClient,
  ~config: ConfigLoader.quotasConfig,
  ~env: dict<string>,
) => Promise.t<array<Domain.quotaData>>
