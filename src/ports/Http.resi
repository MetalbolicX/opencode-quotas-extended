// HTTP port — abstracts the HTTP client used by provider adapters.
// In tests, this is mocked so no live network calls occur.

type fetchContext = {
  signal: option<{ .. }>, // AbortSignal
}

type httpRequest = {
  url: string,
  method: [ #get | #post | #put | #delete ],
  headers: option<dict<string>>,
  body: option<{ .. }>,
}

type httpClient = {
  request: (httpRequest, {
    timeoutMs: float,
    retries: float,
    redact: bool, // always redact secrets in logs
  }) => promise<{ .. }>,
}
