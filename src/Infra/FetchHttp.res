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

// Typed external for creating JS Error objects.
@new external makeFetchError: string => exn = "Error"

// fetchImpl: tests override this ref to stub fetch responses.
// Production code calls installRealFetch() to wire it up to the global fetch API.
let fetchImpl: ref<(string, fetchInit) => promise<JSON.t>> = ref((_url, _init) => {
  Promise.resolve(JSON.Null)
})

// installRealFetch: replace the default stub with a wrapper around the
// global `fetch` API (Node 18+). Production CLI/Plugin entry points must
// call this once during bootstrap; tests leave it on the default stub and
// override per-test as needed.
let installRealFetch = (): unit => {
  let wrapped = (url: string, init: fetchInit): promise<JSON.t> => {
    let webInit: {..} = {
      "method": init.method,
      "headers": init.headers->Option.map(h => h->Dict.toArray->Array.map(((k, v)) => (k, v))),
      "body": init.body,
    }
    Node.globalFetch(url, webInit)
    ->Promise.then((resp: 'b) => {
      let status = Node.responseStatus(resp)
      if status >= 200 && status < 300 {
        Node.responseJson(resp)
      } else {
        Promise.reject(makeFetchError("HTTP " ++ Int.toString(status) ++ ": " ++ url))
      }
    })
  }
  fetchImpl := wrapped
}

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

    let bodyStr = switch req.body {
    | Some(b) => Some(JSON.stringify(b))
    | None => None
    }

    let init: fetchInit = {
      method: methodStr,
      headers: req.headers,
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
