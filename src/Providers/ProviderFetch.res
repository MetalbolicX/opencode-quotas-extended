// src/Providers/ProviderFetch.res
// Template Method: resolve credential -> BearerToken -> fetch -> parse.
// Providers supply only key, buildUrl, parse fn, and http client.
// Based on the canonical fetchQuotas body from Zai.res.

open Domain

type parseFn = JSON.t => array<quotaData>

let fetch = (
  ~key: string,
  ~buildUrl: unit => string,
  ~parse: parseFn,
  ~http: FetchHttp.httpClient,
  ~_logger: FetchHttp.logger,
): Promise.t<array<quotaData>> => {
  CredentialResolver.resolveOrEmpty(~key, ~fn=cred => {
    let authHeader = BearerToken.extract(cred)
    let url = buildUrl()
    let req: FetchHttp.httpRequest = {
      url: url,
      method: #get,
      headers: Some(Dict.fromArray([("Authorization", authHeader)])),
      body: None,
    }
    let opts: FetchHttp.requestOptions = {
      timeoutMs: 15000.0,
      retries: 0.0,
      redact: true,
    }
    http.request(req, opts)
    ->Promise.then(json => {
      Promise.resolve(parse(json))
    })
  })
}
