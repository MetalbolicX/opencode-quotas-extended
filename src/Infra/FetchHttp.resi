// src/Infra/FetchHttp.resi
// HTTP client satisfying the HttpClient port via the global fetch + AbortController.

type logger = {
  debug: (string, option<JSON.t>) => unit,
  info: (string, option<JSON.t>) => unit,
  warn: (string, option<JSON.t>) => unit,
  error: (string, option<JSON.t>) => unit,
}

type httpRequest = {
  url: string,
  method: [#get | #post | #put | #delete],
  headers: option<dict<string>>,
  body: option<JSON.t>,
}

type requestOptions = {
  timeoutMs: float,
  retries: float,
  redact: bool,
}

type fetchInit = {
  method: string,
  headers: option<dict<string>>,
  body: option<string>,
}

type httpClient = {
  request: (httpRequest, requestOptions) => promise<JSON.t>,
}

let noopLogger: logger
let make: (logger) => httpClient
let request: (~logger: logger=?, httpRequest, requestOptions) => promise<JSON.t>
let installRealFetch: (unit) => unit

// Test override point
let fetchImpl: ref<(string, fetchInit) => promise<JSON.t>>
