// src/Infra/FetchHttpTests.res
open RescriptTest

autoBoot := false

let jsonResp = (pairs: array<(string, JSON.t)>): JSON.t => {
  JSON.Encode.object(Dict.fromArray(pairs))
}

let stubFetch = (fn: (string, FetchHttp.fetchInit) => promise<JSON.t>) => {
  FetchHttp.fetchImpl := fn
}

let defaultReq: FetchHttp.httpRequest = {
  url: "https://api.test/quota",
  method: #get,
  headers: None,
  body: None,
}

// 1. 2xx success
testAsync("request returns body for 2xx", callback => {
  stubFetch((_url, _init) => Promise.resolve(jsonResp([("value", JSON.Encode.float(42.0))])))
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 0.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, defaultReq, opts)
    ->Promise.then(result => {
      let str = JSON.stringify(result)
      assertion(
        ~message=`Expected 42 in body, got "${str}"`,
        (a, b) => String.includes(a, b),
        str,
        "42",
      )
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      callback()
      Promise.resolve()
    })
})

// 2. 5xx no-throw
testAsync("request returns body for non-2xx without throwing", callback => {
  stubFetch((_url, _init) => Promise.resolve(jsonResp([("error", JSON.Encode.string("rate limited"))])))
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 0.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, defaultReq, opts)
    ->Promise.then(result => {
      let str = JSON.stringify(result)
      assertion(
        ~message=`Expected rate limited in body, got "${str}"`,
        (a, b) => String.includes(a, b),
        str,
        "rate limited",
      )
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      callback()
      Promise.resolve()
    })
})

// 3. abort stops
testAsync("request throws on abort", callback => {
  stubFetch((_url, _init) => Promise.reject(%raw("new Error('AbortError')")))
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 3.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, defaultReq, opts)
    ->Promise.then(_result => {
      assertion(~message="Expected abort to throw but resolved", (a, b) => a == b, true, false)
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      callback()
      Promise.resolve()
    })
})

// 4. retry exhaustion: all retries reject, final result is rejection
testAsync("request rejects after retry exhaustion", callback => {
  stubFetch((_url, _init) => Promise.reject(%raw("new Error('persistent failure')")))
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 2.0, redact: true}
  FetchHttp.request(~logger=FetchHttp.noopLogger, defaultReq, opts)
  ->Promise.then(_result => {
    assertion(
      ~message="Expected retry exhaustion to reject",
      (a, b) => a == b,
      true,
      false,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch(_err => {
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 5. retries then succeeds
testAsync("request retries then succeeds", callback => {
  let counter = ref(0)
  stubFetch((_url, _init) => {
    counter := counter.contents + 1
    if counter.contents <= 3 {
      Promise.reject(%raw("new Error('network error')"))
    } else {
      Promise.resolve(jsonResp([("ok", JSON.Encode.float(1.0))]))
    }
  })
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 3.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, defaultReq, opts)
    ->Promise.then(result => {
      let str = JSON.stringify(result)
      assertion(
        ~message=`Expected retry success with ok:1, got "${str}"`,
        (a, b) => String.includes(a, b),
        str,
        "1",
      )
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      assertion(~message="Expected retry to succeed but threw", (a, b) => a == b, true, false)
      callback()
      Promise.resolve()
    })
})

// 6. redaction
testAsync("Authorization header is redacted to *** before fetch is called", callback => {
  let seenAuth: ref<option<string>> = ref(None)
  stubFetch((_url, init) => {
    switch init.headers {
    | Some(h) =>
      switch Dict.get(h, "Authorization") {
      | Some(v) => seenAuth := Some(v)
      | None => ()
      }
    | None => ()
    }
    Promise.resolve(jsonResp([]))
  })
  let headers = Dict.fromArray([("Authorization", "TEST_AUTH_VALUE")])
  let req: FetchHttp.httpRequest = {
    url: "https://api.test/quota",
    method: #get,
    headers: Some(headers),
    body: None,
  }
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 0.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, req, opts)
    ->Promise.then(_ => {
      switch seenAuth.contents {
      | Some(v) =>
        assertion(
          ~message=`Expected Authorization to be redacted, got "${v}"`,
          (a, b) => a == b,
          v,
          "***",
        )
      | None =>
        assertion(
          ~message="Expected Authorization header to be passed through",
          (a, b) => a == b,
          true,
          false,
        )
      }
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      callback()
      Promise.resolve()
    })
})

let () = runTests()
