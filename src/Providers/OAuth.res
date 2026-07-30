// src/Providers/OAuth.res
// Testing version - incremental build

type credentialVariant = [ #api | #oauth | #wellknown | #env ]

type apiCredential = {
  variant: string,
  key: string,
}

type oAuthCredential = {
  access: string,
  refresh: string,
  expires: float,
}

type wellknownCredential = {
  key: string,
  token: string,
}

type envCredential = {
  envVar: string,
}

type credential =
  | Api(apiCredential)
  | OAuth(oAuthCredential)
  | Wellknown(wellknownCredential)
  | Env(envCredential)

type credentialSource = {
  get: string => promise<option<credential>>,
}

type httpRequest = {
  url: string,
  method: [ #get | #post | #put | #delete ],
  headers: option<dict<string>>,
  body: option<JSON.t>,
}

type requestOptions = {
  timeoutMs: float,
  retries: float,
  redact: bool,
}

type httpClient = {
  request: (httpRequest, requestOptions) => promise<JSON.t>,
}

let withAuth = (
  client: httpClient,
  cred: credential,
): httpClient => {
  let auth = switch cred {
  | Api(c) => `Bearer ${c.key}`
  | OAuth(c) => `Bearer ${c.access}`
  | Wellknown(c) => `Bearer ${c.token}`
  | Env(c) =>
    let envVal = Node.processEnv->Dict.get(c.envVar)
    switch envVal { | Some(v) => v | None => "" }
  }

  {
    request: (req, opts) => {
      let newHeaders = switch req.headers {
      | Some(h) =>
        let copy = Dict.copy(h)
        let _ = Dict.set(copy, "Authorization", auth)
        Some(copy)
      | None =>
        let d = Dict.make()
        let _ = Dict.set(d, "Authorization", auth)
        Some(d)
      }
      let newReq = { url: req.url, method: req.method, headers: newHeaders, body: req.body }
      client.request(newReq, opts)
    },
  }
}

let statusIs401 = (_err: exn): bool => {
  let s = %raw("Number(err && err.status)")
  s === 401.0
}

// Simplified withOAuth - no inflight tracking
let withOAuth = (
  ~source: credentialSource,
  ~http: httpClient,
  ~providerId: string,
  ~fn: httpClient => Promise.t<array<JSON.t>>,
  ~_timeoutMs: float=15000.0,
): Promise.t<array<JSON.t>> => {
  Promise.make((resolve, reject) => {
    let credOpt = source.get(providerId)
    credOpt->Promise.then(credResult => {
      switch credResult {
      | None => resolve([])
      | Some(c) =>
        let client = withAuth(http, c)
        let result = fn(client)
        result->Promise.then(r => {
          resolve(r)
          Promise.resolve()
        })->Promise.catch(. err => {
          reject(err)
          Promise.resolve()
        })->ignore
      }
      Promise.resolve()
    })->Promise.catch(. err => {
      reject(err)
      Promise.resolve()
    })->ignore
  })
}
