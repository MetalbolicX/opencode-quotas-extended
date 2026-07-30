// src/Providers/Zai.res
// z.ai Coding Plan provider — oauth variant.
// Endpoint: https://api.z.ai/api/monitor/usage/quota/limit

// --- Local type declarations (mirrors port interfaces) -----------------------

type authStrategy = [#api | #oauth | #wellknown | #env]

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<Domain.quotaData>>,
}

// -----------------------------------------------------------------------------

let usageUrl = "https://api.z.ai/api/monitor/usage/quota/limit"

// Extracts Bearer token from Credential.credential
let extractBearerToken = (cred: Credential.credential): string => {
  switch cred {
  | Credential.Api(c) => `Bearer ${c.key}`
  | Credential.OAuth(c) => `Bearer ${c.access}`
  | Credential.Wellknown(c) => `Bearer ${c.token}`
  | Credential.Env(c) =>
    switch Node.processEnv->Dict.get(c.envVar) {
    | Some(v) => v
    | None => ""
    }
  }
}

let createZaiProvider = (): quotaProvider => {
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
        let authHeader = extractBearerToken(cred)
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
            ~isLitePlan=false
          ))
        })
      }
    }),
}
