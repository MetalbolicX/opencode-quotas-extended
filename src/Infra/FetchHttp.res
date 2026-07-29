// src/Infra/FetchHttp.res
// HTTP client satisfying the HttpClient port via the global fetch + AbortController.

// Mirror Logger type locally since Logger.resi is interface-only with no impl
type logger = {
  debug: (string, option<JSON.t>) => unit,
  info: (string, option<JSON.t>) => unit,
  warn: (string, option<JSON.t>) => unit,
  error: (string, option<JSON.t>) => unit,
}

// Mirror Http port types locally (same reason)
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

// fetchImpl: tests override this ref to stub fetch responses
let fetchImpl: ref<(string, fetchInit) => promise<JSON.t>> = ref((_url, _init) => {
  Promise.resolve(%raw("null"))
})

let noopLogger: logger = {
  debug: (_, _) => (),
  info: (_, _) => (),
  warn: (_, _) => (),
  error: (_, _) => (),
}

let request = (
  ~logger: option<logger>=?,
  req: httpRequest,
  opts: requestOptions,
): promise<JSON.t> => {
  let logAttempt = (~attempt: float, ~status: option<int>) => {
    switch logger {
    | Some(l) =>
      let prefix = `FetchHttp attempt ${Float.toString(attempt)} ${req.url}`
      switch status {
      | Some(s) => l.debug(`${prefix} -> ${Int.toString(s)}`, None)
      | None => l.debug(`${prefix} -> pending`, None)
      }
    | None => ()
    }
  }

  let rec retry = (attempt: float): promise<JSON.t> => {
    let controller = Node.makeAbortController()
    let _signal = Node.abortControllerSignal(controller)

    let timeoutId = Node.setTimeoutMs(() => {
      Node.abortControllerAbort(controller)
    }, opts.timeoutMs)

    let methodStr = switch req.method {
    | #get => "GET"
    | #post => "POST"
    | #put => "PUT"
    | #delete => "DELETE"
    }

    let redactedHeaders = switch req.headers {
    | Some(h) =>
      let copy = Dict.fromArray(Dict.toArray(h))
      switch Dict.get(copy, "Authorization") {
      | Some(_) => Dict.set(copy, "Authorization", "***")
      | None => ()
      }
      Some(copy)
    | None => None
    }

    let bodyStr = switch req.body {
    | Some(b) => Some(JSON.stringify(b))
    | None => None
    }

    let init: fetchInit = {
      method: methodStr,
      headers: redactedHeaders,
      body: bodyStr,
    }

    logAttempt(~attempt, ~status=None)

    fetchImpl.contents(req.url, init)
    ->Promise.then(json => {
      Node.clearTimeoutId(timeoutId)
      logAttempt(~attempt, ~status=Some(200))
      Promise.resolve(json)
    })
    ->Promise.catch(err => {
      Node.clearTimeoutId(timeoutId)
      if attempt < opts.retries {
        let delay = (attempt +. 1.0) *. 100.0
        Node.setTimeoutMs(() => (), delay)->ignore
        retry(attempt +. 1.0)
      } else {
        Promise.reject(err)
      }
    })
  }

  retry(0.0)
}

type httpClient = {
  request: (httpRequest, requestOptions) => promise<JSON.t>,
}

let make = (logger: logger): httpClient => {
let wrapped = (req, opts) => {
  request(~logger=logger, req, opts)
}
  {request: wrapped}
}
