// Pure OpenAI OAuth token refresh tests.
open RescriptTest

autoBoot := false

test("needsRefresh applies the 60 second skew boundary", () => {
  assertion(~message="fresh token is not refreshed", (a, b) => a == b, TokenRefresh.needsRefresh(200000.0, 100000.0), false)
  assertion(~message="token at skew boundary is refreshed", (a, b) => a == b, TokenRefresh.needsRefresh(160000.0, 100000.0), true)
  assertion(~message="expired token is refreshed", (a, b) => a == b, TokenRefresh.needsRefresh(90000.0, 100000.0), true)
  assertion(~message="unknown expiry is not proactively refreshed", (a, b) => a == b, TokenRefresh.needsRefresh(0.0, 100000.0), false)
})

test("refresh request is form encoded", () => {
  assertion(
    ~message="refresh request fields and encoding",
    (a, b) => a == b,
    TokenRefresh.refreshRequestBody("dummy access&refresh"),
    "grant_type=refresh_token&refresh_token=dummy%20access%26refresh&client_id=app_EMoamEEZ73f0CkXaXp7hrann",
  )
})

test("refresh response parses required and optional fields", () => {
  let parsed = TokenRefresh.parseRefreshResponse("{\"access_token\":\"dummy-access\",\"refresh_token\":\"dummy-refresh\",\"expires_in\":1800}")
  assertion(~message="access token parsed", (a, b) => a == b, Belt.Option.map(parsed, x => x.access), Some("dummy-access"))
  assertion(~message="rotated refresh token parsed", (a, b) => a == b, Belt.Option.map(parsed, x => x.refresh), Some(Some("dummy-refresh")))
  assertion(~message="expires in parsed", (a, b) => a == b, Belt.Option.map(parsed, x => x.expiresInSeconds), Some(1800.0))

  let noRefresh = TokenRefresh.parseRefreshResponse("{\"access_token\":\"dummy-access\",\"expires_in\":90}")
  assertion(~message="missing refresh is optional", (a, b) => a == b, Belt.Option.map(noRefresh, x => x.refresh), Some(None))

  let noExpiry = TokenRefresh.parseRefreshResponse("{\"access_token\":\"dummy-access\"}")
  assertion(~message="missing expiry defaults to one hour", (a, b) => a == b, Belt.Option.map(noExpiry, x => x.expiresInSeconds), Some(3600.0))

  assertion(~message="missing access token is rejected", (a, b) => a == b, TokenRefresh.parseRefreshResponse("{\"refresh_token\":\"dummy-refresh\"}"), None)
  assertion(~message="malformed JSON is rejected", (a, b) => a == b, TokenRefresh.parseRefreshResponse("not json"), None)
})

let () = runTests()
