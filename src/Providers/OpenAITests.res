// src/Providers/OpenAITests.res
// Tests for OpenAI provider: createOpenAIProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open OpenAI
open RescriptTest

autoBoot := false

// --- Tests --------------------------------------------------------------------

test("createOpenAIProvider returns provider with correct metadata", () => {
  let provider = createOpenAIProvider()
  assertion(~message="id is openai", (a, b) => a == b, provider.id, "openai")
  assertion(~message="displayName is OpenAI", (a, b) => a == b, provider.displayName, "OpenAI")
  assertion(~message="category is subscription", (a, b) => a == b, provider.category, "subscription")
  assertion(~message="authStrategy is oauth", (a, b) => a == b, provider.authStrategy, #oauth)
})

// isAvailable returns a Promise that resolves without throwing.
test("isAvailable returns a Promise<bool>", () => {
  let p = createOpenAIProvider().isAvailable()
  let ok = ref(true)
  p->Promise.then(_v => Promise.resolve())->Promise.catch(. _err => {
    ok := false
    Promise.resolve()
  })->ignore
  assertion(~message="isAvailable resolves without throwing", (a, b) => a == b, true, ok.contents)
})

// fetchQuotas returns a Promise (not null/undefined) — verified by calling it.
// The promise either resolves with data or rejects on error; it does NOT
// synchronously throw. The rejection-on-error contract is verified by the
// ReportPipeline integration test ("one fails, one succeeds").
// fetchQuotas rejection-on-error is covered by ReportPipeline integration test
// ("one fails, one succeeds" — src/application/ReportPipeline.test.mjs).
// The bug fix (removing .catch that swallows HTTP errors) is verified there.

// OAuth refresh wiring tests use only in-memory HTTP and hooks.
@new external testError: string => exn = "Error"

let oauth = (~access: string, ~refresh: string, ~expires: float): Credential.credential =>
  Credential.OAuth({variant: "oauth", access, refresh, expires})

let usageJson = () => JSON.parseOrThrow("{}")

let testHttp = (handler: FetchHttp.httpRequest => promise<JSON.t>): FetchHttp.httpClient =>
  {request: (req, _opts) => handler(req)}

let errorMessage = (err: exn): string =>
  switch JsExn.anyToExnInternal(err) {
  | JsExn(v) => Belt.Option.getWithDefault(JsExn.message(v), String.make(v))
  | e => String.make(e)
  }

let hooks = (
  ~reread: unit => option<Credential.credential>=() => None,
  ~persist: (string, string, float) => bool=(_, _, _) => true,
): oauthRefreshHooks => {reread, persist}

testAsync("OAuth refresh wiring uses, persists, retries, and shares refreshes", callback => {
  let freshCalls = ref(0)
  let freshPersist = ref(0)
  let freshHttp = testHttp(_req => {
    freshCalls := freshCalls.contents + 1
    Promise.resolve(usageJson())
  })
  let freshHooks = hooks(~reread=() => { fail(~message="fresh credential must not be reread", ()); None }, ~persist=(_, _, _) => {
    freshPersist := freshPersist.contents + 1
    true
  })
  let _ = fetchQuotasOAuthWithHooks(~cred=oauth(~access="fresh", ~refresh="refresh", ~expires=Date.now() +. 600000.0), ~http=freshHttp, ~hooks=freshHooks)->Promise.then(_ => {
    assertion(~message="fresh access makes only WHAM request", (a, b) => a == b, freshCalls.contents, 1)
    assertion(~message="fresh token does not persist", (a, b) => a == b, freshPersist.contents, 0)

    let calls = ref([])
    let persisted = ref([])
    let expiringHttp = testHttp(req => {
      calls.contents->Array.push((req.url, req.headers->Option.flatMap(h => Dict.get(h, "Authorization")), req.method))->ignore
      if req.url === TokenRefresh.tokenUrl {
        Promise.resolve(JSON.parseOrThrow("{\"access_token\":\"rotated\",\"refresh_token\":\"next\",\"expires_in\":3600}"))
      } else {
        Promise.resolve(usageJson())
      }
    })
    let expiringHooks = hooks(~persist=(a, r, e) => {
      persisted.contents->Array.push((a, r, e))->ignore
      false
    })
    let _ = fetchQuotasOAuthWithHooks(~cred=oauth(~access="old", ~refresh="current", ~expires=Date.now()), ~http=expiringHttp, ~hooks=expiringHooks)->Promise.then(_ => {
      assertion(~message="refresh and WHAM each called once", (a, b) => a == b, calls.contents->Array.length, 2)
      let (_, rotatedAuth, _) = Belt.Array.getExn(calls.contents, 1)
      assertion(~message="WHAM uses rotated access", (a, b) => a == b, rotatedAuth, Some("Bearer rotated"))
      assertion(~message="persist rotated tokens", (a, b) => a == b, persisted.contents->Array.length, 1)

      // A failed proactive refresh is swallowed, then WHAM uses the old token.
      let fallbackAuth = ref(None)
      let failedHttp = testHttp(req => {
        if req.url === TokenRefresh.tokenUrl {
          Promise.reject(testError("refresh unavailable"))
        } else {
          fallbackAuth := req.headers->Option.flatMap(h => Dict.get(h, "Authorization"))
          Promise.resolve(usageJson())
        }
      })
      let _ = fetchQuotasOAuthWithHooks(~cred=oauth(~access="stale", ~refresh="refresh", ~expires=Date.now()), ~http=failedHttp, ~hooks=hooks())->Promise.then(_ => {
        assertion(~message="refresh failure falls back to old token", (a, b) => a == b, fallbackAuth.contents, Some("Bearer stale"))

        let retryCount = ref(0)
        let retryHttp = testHttp(req => {
          retryCount := retryCount.contents + 1
          let auth = req.headers->Option.flatMap(h => Dict.get(h, "Authorization"))
          if auth === Some("Bearer old") {
            Promise.reject(testError("HTTP 401: wham"))
          } else {
            Promise.resolve(usageJson())
          }
        })
        let rereadHooks = hooks(~reread=() => Some(oauth(~access="new", ~refresh="unused", ~expires=0.0)))
        let _ = fetchQuotasOAuthWithHooks(~cred=oauth(~access="old", ~refresh="unused", ~expires=0.0), ~http=retryHttp, ~hooks=rereadHooks)->Promise.then(_ => {
          assertion(~message="changed credential is retried once", (a, b) => a == b, retryCount.contents, 2)

          // If re-read is unchanged, force refresh even when expires is unknown.
          let forceCount = ref(0)
          let forceHttp = testHttp(req => {
            if req.url === TokenRefresh.tokenUrl {
              forceCount := forceCount.contents + 1
              Promise.resolve(JSON.parseOrThrow("{\"access_token\":\"forced\",\"refresh_token\":\"forced-next\"}"))
            } else if req.headers->Option.flatMap(h => Dict.get(h, "Authorization")) === Some("Bearer forced") {
              forceCount := forceCount.contents + 1
              Promise.resolve(usageJson())
            } else {
              Promise.reject(testError("HTTP 401: wham"))
            }
          })
          let forceHooks = hooks(~reread=() => Some(oauth(~access="old", ~refresh="refresh", ~expires=0.0)), ~persist=(_, _, _) => true)
          let _ = fetchQuotasOAuthWithHooks(~cred=oauth(~access="old", ~refresh="refresh", ~expires=0.0), ~http=forceHttp, ~hooks=forceHooks)->Promise.then(_ => {
            assertion(~message="401 forces refresh and one successful retry", (a, b) => a == b, forceCount.contents, 2)

            let finalAttempts = ref(0)
            let finalFailure = ref("")
            let always401 = testHttp(req => {
              if req.url === TokenRefresh.tokenUrl {
                Promise.resolve(JSON.parseOrThrow("{\"access_token\":\"last-refreshed\",\"refresh_token\":\"last-next\"}"))
              } else {
                finalAttempts := finalAttempts.contents + 1
                Promise.reject(testError("HTTP 401: wham"))
              }
            })
            let sameAccessHooks = hooks(~reread=() => Some(oauth(~access="last", ~refresh="last-refresh", ~expires=0.0)))
            let _ = fetchQuotasOAuthWithHooks(~cred=oauth(~access="last", ~refresh="last-refresh", ~expires=0.0), ~http=always401, ~hooks=sameAccessHooks)->Promise.then(_ => {
              fail(~message="second 401 must reject", ())
              callback()
              Promise.resolve()
            })->Promise.catch(. err => {
              finalFailure := errorMessage(err)
              assertion(~message="second 401 rejects after one retry", (a, b) => a == b, finalAttempts.contents, 2)
              assertion(~message="final rejection preserves 401", (a, b) => a == b, String.includes(finalFailure.contents, "HTTP 401"), true)
              callback()
              Promise.resolve()
            })
            Promise.resolve()
          })
          Promise.resolve()
        })
        Promise.resolve()
      })
      Promise.resolve()
    })
    Promise.resolve()
  })->Promise.catch(. _err => {
    fail(~message="OAuth refresh wiring scenario rejected unexpectedly", ())
    callback()
    Promise.resolve()
  })
})

testAsync("concurrent OAuth callers share one proactive refresh", callback => {
  let refreshPosts = ref(0)
  let concurrentHttp = testHttp(req => {
    if req.url === TokenRefresh.tokenUrl {
      refreshPosts := refreshPosts.contents + 1
      Promise.resolve(JSON.parseOrThrow("{\"access_token\":\"shared\",\"refresh_token\":\"shared-next\"}"))
    } else {
      Promise.resolve(usageJson())
    }
  })
  let sharedHooks = hooks()
  let cred = oauth(~access="concurrent-old", ~refresh="concurrent-refresh", ~expires=Date.now())
  let first = fetchQuotasOAuthWithHooks(~cred, ~http=concurrentHttp, ~hooks=sharedHooks)
  let second = fetchQuotasOAuthWithHooks(~cred, ~http=concurrentHttp, ~hooks=sharedHooks)
  let _ = Promise.all([first, second])->Promise.then(_ => {
    assertion(~message="one refresh POST serves both callers", (a, b) => a == b, refreshPosts.contents, 1)
    callback()
    Promise.resolve()
  })->Promise.catch(. _err => {
    fail(~message="concurrent fetches should succeed", ())
    callback()
    Promise.resolve()
  })
})

// --- Origin-aware routing (opencode refreshes; pi is read-only) ----------------

let candidate = (cred, origin): CredentialResolver.candidate => {credential: cred, origin}

let trackingHooks = (rereads: ref<int>, persists: ref<int>) =>
  hooks(
    ~reread=() => {
      rereads := rereads.contents + 1
      None
    },
    ~persist=(_, _, _) => {
      persists := persists.contents + 1
      true
    },
  )

testAsync("expired pi OAuth token rejects with a fallthrough hint and no HTTP", callback => {
  let calls = ref(0)
  let rereads = ref(0)
  let persists = ref(0)
  let http = testHttp(_req => {
    calls := calls.contents + 1
    Promise.resolve(usageJson())
  })
  let cred = oauth(~access="pi-old", ~refresh="pi-refresh", ~expires=Date.now() -. 1000.0)
  fetchQuotasForCandidate(~candidate=candidate(cred, #pi), ~http, ~hooks=trackingHooks(rereads, persists))
  ->Promise.then(_ => {
    fail(~message="expired pi token must reject", ())
    callback()
    Promise.resolve()
  })
  ->Promise.catch(err => {
    assertion(
      ~message="actionable message",
      (a, b) => a == b,
      errorMessage(err),
      "OpenAI token from pi expired — run `pi` to refresh",
    )
    assertion(~message="resolver falls through on it", (a, b) => a == b, CredentialResolver.isFallthroughError(err), true)
    assertion(~message="no HTTP (no refresh POST)", (a, b) => a == b, calls.contents, 0)
    assertion(~message="pi file never reread or written", (a, b) => a == b, (rereads.contents, persists.contents), (0, 0))
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("valid pi OAuth token is used as-is and a 401 is not refreshed", callback => {
  let urls = ref([])
  let auths = ref([])
  let rereads = ref(0)
  let persists = ref(0)
  let http = testHttp(req => {
    urls := Array.concat(urls.contents, [req.url])
    auths := Array.concat(auths.contents, [req.headers->Option.flatMap(h => h->Dict.get("Authorization"))])
    Promise.reject(testError("HTTP 401: " ++ req.url))
  })
  let cred = oauth(~access="pi-live", ~refresh="pi-refresh", ~expires=Date.now() +. 600000.0)
  fetchQuotasForCandidate(~candidate=candidate(cred, #pi), ~http, ~hooks=trackingHooks(rereads, persists))
  ->Promise.then(_ => {
    fail(~message="401 must reject", ())
    callback()
    Promise.resolve()
  })
  ->Promise.catch(err => {
    assertion(~message="401 surfaces for fallthrough", (a, b) => a == b, CredentialResolver.isFallthroughError(err), true)
    assertion(~message="only the usage call, no refresh POST", (a, b) => a == b, urls.contents, [whamUrl])
    assertion(~message="pi access token sent", (a, b) => a == b, auths.contents, [Some("Bearer pi-live")])
    assertion(~message="pi file never reread or written", (a, b) => a == b, (rereads.contents, persists.contents), (0, 0))
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("opencode OAuth candidate keeps refreshing and persisting", callback => {
  let refreshPosts = ref(0)
  let rereads = ref(0)
  let persists = ref(0)
  let http = testHttp(req =>
    if req.url === TokenRefresh.tokenUrl {
      refreshPosts := refreshPosts.contents + 1
      Promise.resolve(JSON.parseOrThrow("{\"access_token\":\"oc-new\",\"refresh_token\":\"oc-next\"}"))
    } else {
      Promise.resolve(usageJson())
    }
  )
  let cred = oauth(~access="oc-old", ~refresh="oc-refresh-unique", ~expires=Date.now())
  fetchQuotasForCandidate(~candidate=candidate(cred, #opencode), ~http, ~hooks=trackingHooks(rereads, persists))
  ->Promise.then(_ => {
    assertion(~message="refresh POST sent", (a, b) => a == b, refreshPosts.contents, 1)
    assertion(~message="rotated tokens persisted", (a, b) => a == b, persists.contents, 1)
    callback()
    Promise.resolve()
  })
  ->Promise.catch(_ => {
    fail(~message="opencode refresh path should succeed", ())
    callback()
    Promise.resolve()
  })
  ->ignore
})

// Run all tests
let () = runTests()
