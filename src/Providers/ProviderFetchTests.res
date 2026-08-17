// src/Providers/ProviderFetchTests.res
// Tests for ProviderFetch — stub fetch, 2 key scenarios:
// no-credential -> [] (provider failures MUST reject per project invariant).
open RescriptTest

autoBoot := false

// PF1: no credential -> []
testAsync("PF1: no credential returns []", callback => {
  FetchHttp.fetchImpl.contents = (_url, _init) => Promise.resolve(JSON.Encode.null)
  let http = FetchHttp.make(FetchHttp.noopLogger)
  let parse = (_json: JSON.t): array<Domain.quotaData> => []
  let result = ProviderFetch.fetch(
    ~key="no-such-provider",
    ~buildUrl=() => "https://api.test/quota",
    ~parse=parse,
    ~http=http,
    ~_logger=FetchHttp.noopLogger,
  )
  let _ = result->Promise.then(arr => {
    assertion(
      ~message="PF1: Expected [] when no credential",
      (a, b) => a == b,
      arr,
      [],
    )
    callback()
    Promise.resolve()
  })->Promise.catch((. _err) => {
    assertion(~message="PF1: should not reject", (a, b) => a == b, false, true)
    callback()
    Promise.resolve()
  })
})

let () = runTests()
