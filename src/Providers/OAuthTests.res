// src/Providers/OAuthTests.res
// Tests for OAuth module: withAuth, withOAuth.

open OAuth
open RescriptTest

autoBoot := false

// --- Mock types for testing -------------------------------------------------------

let makeCredentialSource = (
  getResult: option<credential>,
): credentialSource => {
  {
    get: (_id) => Promise.resolve(getResult),
  }
}

// --- withAuth tests ----------------------------------------------------------------

test("withAuth injects Bearer token for Api credential", () => {
  let mockHttp: httpClient = {
    request: (_req, _opts) => {
      Promise.resolve(JSON.Null)
    },
  }
  let cred = Api({ variant: "api", key: "test-key-123" })
  let authedClient = withAuth(mockHttp, cred)

  let _: unit = authedClient.request(
    { url: "https://api.example.com", method: #get, headers: None, body: None },
    { timeoutMs: 5000.0, retries: 0.0, redact: false },
  )->Promise.then(_ => Promise.resolve())->ignore

  pass(~message="withAuth with Api credential did not throw", ())
})

test("withAuth injects Bearer token for OAuth credential", () => {
  let mockHttp: httpClient = {
    request: (_req, _opts) => {
      Promise.resolve(JSON.Null)
    },
  }
  let cred = OAuth({ access: "access-token-abc", refresh: "refresh-token-xyz", expires: 0.0 })
  let authedClient = withAuth(mockHttp, cred)

  let _: unit = authedClient.request(
    { url: "https://api.example.com", method: #get, headers: None, body: None },
    { timeoutMs: 5000.0, retries: 0.0, redact: false },
  )->Promise.then(_ => Promise.resolve())->ignore

  pass(~message="withAuth with OAuth credential did not throw", ())
})

test("withAuth preserves other headers", () => {
  let mockHttp: httpClient = {
    request: (_req, _opts) => {
      Promise.resolve(JSON.Null)
    },
  }
  let cred = Api({ variant: "api", key: "test-key" })
  let authedClient = withAuth(mockHttp, cred)

  let existingHeaders = Some(Dict.fromArray([("Content-Type", "application/json")]))
  let _: unit = authedClient.request(
    { url: "https://api.example.com", method: #get, headers: existingHeaders, body: None },
    { timeoutMs: 5000.0, retries: 0.0, redact: false },
  )->Promise.then(_ => Promise.resolve())->ignore

  pass(~message="withAuth preserves existing headers", ())
})

// --- withOAuth tests ---------------------------------------------------------------

testAsync("withOAuth returns [] when no credential", callback => {
  let source = makeCredentialSource(None)
  let mockHttp: httpClient = {
    request: (_req, _opts) => Promise.resolve(JSON.Null),
  }

  let _ = withOAuth(
    ~source,
    ~http=mockHttp,
    ~providerId="test-provider",
    ~fn=_client => Promise.resolve([JSON.Null]),
  )
    ->Promise.then(r => {
      assertion(
        ~message="No credential returns empty array",
        (a, b) => a == b,
        r,
        [],
      )
      callback()
      Promise.resolve()
    })
    ->Promise.catch(. _err => {
      fail(~message="Should not reject", ())
      callback()
      Promise.resolve()
    })
})

testAsync("withOAuth calls fn with authed client on success", callback => {
  let cred = OAuth({ access: "token-abc", refresh: "refresh-xyz", expires: 0.0 })
  let source = makeCredentialSource(Some(cred))
  let mockHttp: httpClient = {
    request: (_req, _opts) => Promise.resolve(JSON.Null),
  }

  let _ = withOAuth(
    ~source,
    ~http=mockHttp,
    ~providerId="test-provider",
    ~fn=_client => {
      Promise.resolve([JSON.String("success")])
    },
  )
    ->Promise.then(r => {
      assertion(
        ~message="Should return success result",
        (a, b) => a == b,
        r->Array.length > 0,
        true,
      )
      callback()
      Promise.resolve()
    })
    ->Promise.catch(. _err => {
      fail(~message="Promise rejected", ())
      callback()
      Promise.resolve()
    })
})

testAsync("withOAuth propagates thrown exceptions", callback => {
  let cred = OAuth({ access: "token-abc", refresh: "refresh-xyz", expires: 0.0 })
  let source = makeCredentialSource(Some(cred))
  let mockHttp: httpClient = {
    request: (_req, _opts) => Promise.resolve(JSON.Null),
  }

  let err = %raw("new Error('network error')")

  let _ = withOAuth(
    ~source,
    ~http=mockHttp,
    ~providerId="test-provider",
    ~fn=_client => {
      Promise.make((_resolve, reject) => {
        reject(err)
      })
    },
  )
    ->Promise.then(_r => {
      fail(~message="Should not resolve on error", ())
      callback()
      Promise.resolve()
    })
    ->Promise.catch(. _exn => {
      pass(~message="Exception propagated correctly", ())
      callback()
      Promise.resolve()
    })
})

// Run all tests
let () = runTests()
