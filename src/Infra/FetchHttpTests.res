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

// 6. Authorization is forwarded unchanged on the wire (NOT redacted before fetch)
testAsync("real Authorization header is forwarded unchanged on the wire", callback => {
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
  let headers = Dict.fromArray([("Authorization", "Bearer TEST_AUTH_VALUE")])
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
          ~message=`Expected real Authorization to reach fetch, got "${v}"`,
          (a, b) => a == b,
          v,
          "Bearer TEST_AUTH_VALUE",
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

// 7. non-Authorization headers are preserved verbatim
testAsync("Non-Authorization headers preserved verbatim", callback => {
  let seenHeaders: ref<option<Dict.t<string>>> = ref(None)
  stubFetch((_url, init) => {
    switch init.headers {
    | Some(h) => seenHeaders := Some(h)
    | None => seenHeaders := Some(Dict.make())
    }
    Promise.resolve(jsonResp([]))
  })
  let headers = Dict.fromArray([("X-Custom", "foo"), ("Content-Type", "application/json")])
  let req: FetchHttp.httpRequest = {
    url: "https://api.test/quota",
    method: #get,
    headers: Some(headers),
    body: None,
  }
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 0.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, req, opts)
    ->Promise.then(_ => {
      switch seenHeaders.contents {
      | Some(h) =>
        assertion(
          ~message=`Expected X-Custom to be foo, got "${Dict.get(h, "X-Custom")->Option.getWithDefault("")}"`,
          (a, b) => a == b,
          Dict.get(h, "X-Custom")->Option.getWithDefault(""),
          "foo",
        )
        assertion(
          ~message=`Expected Content-Type to be application/json, got "${Dict.get(h, "Content-Type")->Option.getWithDefault("")}"`,
          (a, b) => a == b,
          Dict.get(h, "Content-Type")->Option.getWithDefault(""),
          "application/json",
        )
      | None =>
        assertion(~message="Expected headers to be Some", (a, b) => a == b, true, false)
      }
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      callback()
      Promise.resolve()
    })
})

// 8. no headers at all → init.headers === None
testAsync("No headers at all sends None to fetch", callback => {
  let seenHeaders: ref<option<option<Dict.t<string>>>> = ref(None)
  stubFetch((_url, init) => {
    seenHeaders := Some(init.headers)
    Promise.resolve(jsonResp([]))
  })
  let req: FetchHttp.httpRequest = {
    url: "https://api.test/quota",
    method: #get,
    headers: None,
    body: None,
  }
  let opts: FetchHttp.requestOptions = {timeoutMs: 5000.0, retries: 0.0, redact: true}
  let _ = FetchHttp.request(~logger=FetchHttp.noopLogger, req, opts)
    ->Promise.then(_ => {
      switch seenHeaders.contents {
      | Some(None) =>
        assertion(~message="Expected headers to be None", (a, b) => a == b, true, true)
      | Some(Some(_)) =>
        assertion(~message="Expected headers to be None, got Some", (a, b) => a == b, false, true)
      | None =>
        assertion(~message="Expected headers callback to have fired", (a, b) => a == b, false, true)
      }
      callback()
      Promise.resolve()
    })
    ->Promise.catch((. _err) => {
      callback()
      Promise.resolve()
    })
})

// 9. Authorization + other headers → all reach fetch, in original order
testAsync("Authorization plus other headers all reach fetch unchanged", callback => {
  let seenAuth: ref<option<string>> = ref(None)
  let seenAccept: ref<option<string>> = ref(None)
  stubFetch((_url, init) => {
    switch init.headers {
    | Some(h) =>
      seenAuth := Dict.get(h, "Authorization")
      seenAccept := Dict.get(h, "Accept")
    | None => ()
    }
    Promise.resolve(jsonResp([]))
  })
  let headers = Dict.fromArray([("Authorization", "Bearer T"), ("Accept", "application/json")])
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
          ~message=`Expected Authorization to be Bearer T, got "${v}"`,
          (a, b) => a == b,
          v,
          "Bearer T",
        )
      | None =>
        assertion(~message="Expected Authorization header", (a, b) => a == b, false, true)
      }
      switch seenAccept.contents {
      | Some(v) =>
        assertion(
          ~message=`Expected Accept to be application/json, got "${v}"`,
          (a, b) => a == b,
          v,
          "application/json",
        )
      | None =>
        assertion(~message="Expected Accept header", (a, b) => a == b, false, true)
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
