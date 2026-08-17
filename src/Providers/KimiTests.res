// src/Providers/KimiTests.res
// Tests for Kimi provider: createKimiProvider.
// Tests provider metadata (id, displayName, category, authStrategy).
// HTTP parsing logic is covered by CodingPlanParseTests.

open Kimi
open RescriptTest

autoBoot := false

// --- Tests ---------------------------------------------------------------------

test("createKimiProvider returns provider with correct metadata", () => {
  let provider = createKimiProvider()
  assertion(~message="id is kimi", (a, b) => a == b, provider.id, "kimi")
  assertion(~message="displayName is Kimi / Moonshot", (a, b) => a == b, provider.displayName, "Kimi / Moonshot")
  assertion(~message="category is coding-plan", (a, b) => a == b, provider.category, "coding-plan")
  assertion(~message="authStrategy is oauth", (a, b) => a == b, provider.authStrategy, #oauth)
})

// T2.3 — buildRequest contract (REQ-K-5 s1)
test("buildRequest returns GET to correct URL with Bearer and Accept headers", () => {
  let req = buildRequest("Bearer abc")
  assertion(~message="method is GET", (a, b) => a == b, req.method, #get)
  assertion(~message="url is api.kimi.com", (a, b) => a == b, req.url, "https://api.kimi.com/coding/v1/usages")
  switch req.headers {
  | Some(headers) =>
    assertion(~message="Authorization header present", (a, b) => a == b, Dict.get(headers, "Authorization"), Some("Bearer abc"))
    assertion(~message="Accept header present", (a, b) => a == b, Dict.get(headers, "Accept"), Some("application/json"))
  | None => assertion(~message="headers should be Some", (a, b) => a == b, true, false)
  }
  assertion(~message="body is None", (a, b) => a == b, req.body, None)
})

// T2.3 — requestOptions contract
test("requestOptions has correct timeout, retries, and redact", () => {
  assertion(~message="timeoutMs is 15000", (a, b) => a == b, requestOptions.timeoutMs, 15000.0)
  assertion(~message="retries is 0", (a, b) => a == b, requestOptions.retries, 0.0)
  assertion(~message="redact is true", (a, b) => a == b, requestOptions.redact, true)
})

// T2.4 — no credential: CredentialResolver.resolve("kimi") returns None
// which makes fetchQuotas resolve to []. This is the same pattern as
// MinimaxTests (covered by ReportPipeline integration tests, not unit-tested here).
// The pure contract is: when no credential is available, the provider is still
// registered and callable without throwing.

// Run all tests
let () = runTests()
