// OpenAI provider interface — cross-module surface.
type oauthRefreshHooks = {
  reread: unit => option<Credential.credential>,
  persist: (string, string, float) => bool,
}

let fetchQuotasOAuthWithHooks: (~cred: Credential.credential, ~http: FetchHttp.httpClient, ~hooks: oauthRefreshHooks) => Promise.t<array<Domain.quotaData>>
let createOpenAIProvider: unit => Provider.quotaProvider
