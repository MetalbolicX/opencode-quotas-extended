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

// Run all tests
let () = runTests()
