// ReportPipelineReasonTests.res — rejected provider reason formatting
open RescriptTest

testAsync("stringifyReason unwraps a caught JsExn Error", testDone => {
  let rawErr = %raw("new Error('HTTP 401: https://example.com')")
  let wrappedP = Promise.reject(rawErr)
    ->Promise.catch(e => Promise.resolve(e))
  let _ = wrappedP->Promise.then(wrapped => {
    assertion(
      ~message="wrapped Error message is preserved",
      (a, b) => a == b,
      ReportPipeline.stringifyReason(wrapped),
      "HTTP 401: https://example.com",
    )
    testDone(~planned=1, ())
    Promise.resolve()
  })
  ()
})

test("stringifyReason extracts a raw Error message", () => {
  let rawErr = %raw("new Error('boom')")
  assertion(~message="raw Error message is extracted", (a, b) => a == b, ReportPipeline.stringifyReason(rawErr), "boom")
})

test("stringifyReason preserves a plain string", () => {
  assertion(~message="plain string is unchanged", (a, b) => a == b, ReportPipeline.stringifyReason("failure"), "failure")
})

test("stringifyReason stringifies a scalar", () => {
  assertion(~message="scalar has a string fallback", (a, b) => a == b, ReportPipeline.stringifyReason(42), "42")
})

let () = runTests()
