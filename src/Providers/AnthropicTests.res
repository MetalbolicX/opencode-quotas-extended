// src/Providers/AnthropicTests.res
// Tests for the Anthropic provider: metadata, Claude Code subscription parsing,
// and candidate routing (subscription vs admin fallback). All HTTP is in-memory
// and every credential file lives under an isolated os.tmpdir() root.
open Anthropic
open RescriptTest

autoBoot := false

@new external testError: string => exn = "Error"

let testHttp = (handler: FetchHttp.httpRequest => promise<JSON.t>): FetchHttp.httpClient =>
  {request: (req, _opts) => handler(req)}

let errorMessage = (err: exn): string =>
  switch JsExn.anyToExnInternal(err) {
  | JsExn(v) => Belt.Option.getWithDefault(JsExn.message(v), String.make(v))
  | e => String.make(e)
  }

let counter = ref(0)

let makeDir = (): string => {
  counter := counter.contents + 1
  let root =
    Node.osTmpdir() ++ "/anthropic-test-" ++ String.make(Date.now()) ++ "-" ++ Int.toString(counter.contents)
  let _ = Node.mkdirSync(root)
  root
}

let cleanup = (root: string): unit => Node.rmSyncRecursive(root, {recursive: true, force: true})

let writeClaude = (root: string, json: string): unit =>
  Node.writeFileSync(root ++ "/.credentials.json", json)

let claudeCredential = (~root: string): Credential.credential => {
  let env = Dict.fromArray([("CLAUDE_CONFIG_DIR", root)])
  switch ClaudeCodeSource.getCredential(~env=Some(env)) {
  | Some(credential) => credential
  | None =>
    fail(~message="expected a decoded Claude Code credential", ())
    Credential.Api({variant: "api", key: ""})
  }
}

let claudeCandidate = (~root: string, expires: float): CredentialResolver.candidate => {
  let _ = writeClaude(
    root,
    `{"claudeAiOauth":{"accessToken":"cc-access","refreshToken":"cc-refresh","expiresAt":${Belt.Float.toString(expires)}}}`,
  )
  {credential: claudeCredential(~root), origin: #claudeCode}
}

// ─── Metadata ─────────────────────────────────────────────────────────────────

test("createAnthropicProvider returns provider with correct metadata", () => {
  let provider = createAnthropicProvider()
  assertion(~message="id is anthropic", (a, b) => a == b, provider.id, "anthropic")
  assertion(~message="displayName is Anthropic", (a, b) => a == b, provider.displayName, "Anthropic")
  assertion(~message="category is subscription", (a, b) => a == b, provider.category, "subscription")
  assertion(~message="authStrategy is oauth", (a, b) => a == b, provider.authStrategy, #oauth)
})

// ─── Subscription parser (pure) ───────────────────────────────────────────────

let sessionReset = "2025-09-01T12:00:00Z"
let weeklyReset = "2025-09-05T12:00:00Z"

let l6Fixture = () =>
  JSON.parseOrThrow(
    `{"five_hour":{"utilization":7,"resets_at":"${sessionReset}"},"seven_day":{"utilization":4,"resets_at":"${weeklyReset}"},"seven_day_opus":null,"seven_day_sonnet":null,"limits":[{"kind":"session","group":"five_hour","percent":7,"resets_at":"${sessionReset}","scope":null},{"kind":"weekly_all","group":"seven_day","percent":4,"resets_at":"${weeklyReset}","scope":null},{"kind":"weekly_scoped","group":"seven_day","percent":0,"resets_at":"${weeklyReset}","scope":{"model":{"display_name":"Fable"}}}]}`,
  )

let resetMs = (q: Domain.quotaData): float =>
  switch q.reset {
  | Some(d) => Date.getTime(d)
  | None => -1.0
  }

let expectedMs = (iso: string): float => Node.jsDateParse(iso)

test("parseSubscriptionUsage reads limits[] into exact rows", () => {
  let rows = parseSubscriptionUsage(l6Fixture())
  assertion(~message="row count", (a, b) => a == b, rows->Array.length, 3)

  let session = rows->Belt.Array.getExn(0)
  assertion(~message="session id", (a, b) => a == b, session.id, "anthropic-session")
  assertion(
    ~message="session providerName",
    (a, b) => a == b,
    session.providerName,
    `Anthropic\u00A0·\u00A05h rolling window`,
  )
  assertion(~message="session info", (a, b) => a == b, session.info, Some("5h rolling window"))
  assertion(~message="session used", (a, b) => a == b, session.used, 7.0)
  assertion(~message="session limit", (a, b) => a == b, session.limit, Some(100.0))
  assertion(~message="session unit", (a, b) => a == b, session.unit, "%")
  assertion(~message="session reset", (a, b) => a == b, resetMs(session), expectedMs(sessionReset))
  assertion(~message="session window", (a, b) => a == b, session.window, #rolling5h)

  let weekly = rows->Belt.Array.getExn(1)
  assertion(~message="weekly id", (a, b) => a == b, weekly.id, "anthropic-weekly")
  assertion(
    ~message="weekly providerName",
    (a, b) => a == b,
    weekly.providerName,
    `Anthropic\u00A0·\u00A0Weekly limit`,
  )
  assertion(~message="weekly info", (a, b) => a == b, weekly.info, Some("Weekly limit"))
  assertion(~message="weekly used", (a, b) => a == b, weekly.used, 4.0)
  assertion(~message="weekly limit", (a, b) => a == b, weekly.limit, Some(100.0))
  assertion(~message="weekly unit", (a, b) => a == b, weekly.unit, "%")
  assertion(~message="weekly reset", (a, b) => a == b, resetMs(weekly), expectedMs(weeklyReset))
  assertion(~message="weekly window", (a, b) => a == b, weekly.window, #rollingWeekly)

  let scoped = rows->Belt.Array.getExn(2)
  assertion(~message="scoped id", (a, b) => a == b, scoped.id, "anthropic-weekly-scoped-Fable")
  assertion(
    ~message="scoped providerName",
    (a, b) => a == b,
    scoped.providerName,
    `Anthropic\u00A0·\u00A0Weekly limit (Fable)`,
  )
  assertion(~message="scoped info", (a, b) => a == b, scoped.info, Some("Weekly limit (Fable)"))
  assertion(~message="scoped used", (a, b) => a == b, scoped.used, 0.0)
  assertion(~message="scoped reset", (a, b) => a == b, resetMs(scoped), expectedMs(weeklyReset))
})

test("parseSubscriptionUsage falls back to five_hour/seven_day and skips nulls", () => {
  let fixture =
    JSON.parseOrThrow(
      `{"five_hour":{"utilization":7,"resets_at":"${sessionReset}"},"seven_day":{"utilization":4,"resets_at":"${weeklyReset}"},"seven_day_opus":null,"seven_day_sonnet":{"utilization":null,"resets_at":"${weeklyReset}"}}`,
    )
  let rows = parseSubscriptionUsage(fixture)
  assertion(~message="row count", (a, b) => a == b, rows->Array.length, 2)
  assertion(~message="ids", (a, b) => a == b, rows->Array.map(r => r.id), [
    "anthropic-five-hour",
    "anthropic-seven-day",
  ])
  assertion(~message="five-hour used", (a, b) => a == b, (rows->Belt.Array.getExn(0)).used, 7.0)
  assertion(~message="seven-day used", (a, b) => a == b, (rows->Belt.Array.getExn(1)).used, 4.0)
  assertion(~message="seven-day reset", (a, b) => a == b, resetMs(rows->Belt.Array.getExn(1)), expectedMs(weeklyReset))
})

test("parseSubscriptionUsage clamps out-of-range percents", () => {
  let fixture =
    JSON.parseOrThrow(
      `{"limits":[{"kind":"session","percent":150,"resets_at":null,"scope":null},{"kind":"weekly_all","percent":-5,"resets_at":null,"scope":null}]}`,
    )
  let rows = parseSubscriptionUsage(fixture)
  assertion(~message="high clamped", (a, b) => a == b, (rows->Belt.Array.getExn(0)).used, 100.0)
  assertion(~message="low clamped", (a, b) => a == b, (rows->Belt.Array.getExn(1)).used, 0.0)
  assertion(~message="missing reset stays None", (a, b) => a == b, (rows->Belt.Array.getExn(0)).reset, None)
})

test("parseSubscriptionUsage keeps unknown limit kinds generically", () => {
  let fixture = JSON.parseOrThrow(`{"limits":[{"kind":"monthly_all","percent":12,"resets_at":null,"scope":null}]}`)
  let rows = parseSubscriptionUsage(fixture)
  assertion(~message="generic id", (a, b) => a == b, (rows->Belt.Array.getExn(0)).id, "anthropic-monthly_all")
  assertion(~message="generic label", (a, b) => a == b, (rows->Belt.Array.getExn(0)).info, Some("monthly_all"))
})

// ─── Subscription fetch (injected http) ───────────────────────────────────────

testAsync("expired Claude Code token rejects with the refresh hint and no HTTP", callback => {
  let root = makeDir()
  let candidate = claudeCandidate(~root, Date.now() -. 60_000.0)
  let before = Node.readFileSyncUtf8(root ++ "/.credentials.json", {encoding: "utf8"})
  let calls = ref(0)
  let http = testHttp(_req => {
    calls := calls.contents + 1
    Promise.resolve(JSON.parseOrThrow("{}"))
  })
  fetchQuotasForCandidate(~candidate, ~http, ~config=ConfigLoader.defaults, ~env=Dict.make())
  ->Promise.then(_rows => {
    fail(~message="expected rejection for an expired token", ())
    cleanup(root)
    callback()
    Promise.resolve()
  })
  ->Promise.catch(err => {
    assertion(
      ~message="exact expiry message",
      (a, b) => a == b,
      errorMessage(err),
      "Claude Code token expired — run `claude` to refresh",
    )
    assertion(
      ~message="fallthrough-able",
      (a, b) => a == b,
      CredentialResolver.isFallthroughError(err),
      true,
    )
    assertion(~message="no HTTP call", (a, b) => a == b, calls.contents, 0)
    assertion(
      ~message="credentials file unchanged",
      (a, b) => a == b,
      Node.readFileSyncUtf8(root ++ "/.credentials.json", {encoding: "utf8"}),
      before,
    )
    cleanup(root)
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("valid Claude Code token sends one GET with OAuth headers", callback => {
  let root = makeDir()
  let candidate = claudeCandidate(~root, Date.now() +. 600_000.0)
  let calls = ref([])
  let http = testHttp(req => {
    calls.contents->Array.push(req)->ignore
    Promise.resolve(l6Fixture())
  })
  fetchQuotasForCandidate(~candidate, ~http, ~config=ConfigLoader.defaults, ~env=Dict.make())
  ->Promise.then(rows => {
    assertion(~message="one request", (a, b) => a == b, calls.contents->Array.length, 1)
    assertion(~message="three rows", (a, b) => a == b, rows->Array.length, 3)
    let req = calls.contents->Belt.Array.getExn(0)
    assertion(~message="oauth usage URL", (a, b) => a == b, req.url, oauthUsageUrl)
    assertion(~message="method GET", (a, b) => a == b, req.method, #get)
    assertion(
      ~message="bearer access",
      (a, b) => a == b,
      req.headers->Option.flatMap(h => Dict.get(h, "Authorization")),
      Some("Bearer cc-access"),
    )
    assertion(
      ~message="oauth beta header",
      (a, b) => a == b,
      req.headers->Option.flatMap(h => Dict.get(h, "anthropic-beta")),
      Some("oauth-2025-04-20"),
    )
    cleanup(root)
    callback()
    Promise.resolve()
  })
  ->Promise.catch(. _err => {
    fail(~message="valid token fetch should succeed", ())
    cleanup(root)
    callback()
    Promise.resolve()
  })
  ->ignore
})

testAsync("HTTP 401 from the subscription endpoint rejects without another request", callback => {
  let root = makeDir()
  let candidate = claudeCandidate(~root, Date.now() +. 600_000.0)
  let calls = ref(0)
  let http = testHttp(req => {
    calls := calls.contents + 1
    Promise.reject(testError("HTTP 401: " ++ req.url))
  })
  fetchQuotasForCandidate(~candidate, ~http, ~config=ConfigLoader.defaults, ~env=Dict.make())
  ->Promise.then(_rows => {
    fail(~message="expected rejection on 401", ())
    cleanup(root)
    callback()
    Promise.resolve()
  })
  ->Promise.catch(err => {
    assertion(~message="401 preserved", (a, b) => a == b, String.includes(errorMessage(err), "HTTP 401"), true)
    assertion(~message="fallthrough-able", (a, b) => a == b, CredentialResolver.isFallthroughError(err), true)
    assertion(~message="one request only", (a, b) => a == b, calls.contents, 1)
    cleanup(root)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// ─── Admin fallback routing ───────────────────────────────────────────────────

testAsync("non-claudeCode Api candidate routes to the admin path, never oauth usage", callback => {
  let config = {...ConfigLoader.defaults, anthropic: Some({orgId: Some("org-1")})}
  let candidate: CredentialResolver.candidate = {
    credential: Credential.Api({variant: "api", key: "admin-key"}),
    origin: #opencode,
  }
  let calls = ref([])
  let http = testHttp(req => {
    calls.contents->Array.push(req.url)->ignore
    Promise.resolve(
      JSON.parseOrThrow(
        `{"data":[{"model":"claude-opus-4","time_bucket":"2025-09-01","usage":{"input_tokens":10,"output_tokens":5}}],"has_more":false}`,
      ),
    )
  })
  fetchQuotasForCandidate(~candidate, ~http, ~config, ~env=Dict.make())
  ->Promise.then(rows => {
    assertion(~message="never calls oauth usage", (a, b) => a == b, calls.contents->Array.includes(oauthUsageUrl), false)
    assertion(
      ~message="calls admin usage for the org",
      (a, b) => a == b,
      calls.contents->Array.some(u => String.includes(u, "api.anthropic.com/v1/organizations/org-1/usage")),
      true,
    )
    assertion(~message="admin row parsed", (a, b) => a == b, rows->Array.length, 1)
    assertion(~message="admin token total", (a, b) => a == b, (rows->Belt.Array.getExn(0)).used, 15.0)
    callback()
    Promise.resolve()
  })
  ->Promise.catch(. _err => {
    fail(~message="admin path should resolve", ())
    callback()
    Promise.resolve()
  })
  ->ignore
})

let () = runTests()
