// ReportPipelineReasonTests.res — rejected provider reason formatting
open RescriptTest

testAsync("stringifyReason unwraps a caught JsExn Error", testDone => {
  let jsErr = JsExn.anyToExnInternal(JsError.make("HTTP 401: https://example.com"))
  let wrappedP = Promise.reject(jsErr)
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
  let jsErr = JsExn.anyToExnInternal(JsError.make("boom"))
  assertion(~message="raw Error message is extracted", (a, b) => a == b, ReportPipeline.stringifyReason(jsErr), "boom")
})

test("stringifyReason preserves a plain string", () => {
  // Wrap like the JS runtime does when a string is thrown and caught.
  let exn = JsExn.anyToExnInternal("failure")
  assertion(~message="plain string is unchanged", (a, b) => a == b, ReportPipeline.stringifyReason(exn), "failure")
})

test("stringifyReason stringifies a scalar", () => {
  let exn = JsExn.anyToExnInternal(42)
  assertion(~message="scalar has a string fallback", (a, b) => a == b, ReportPipeline.stringifyReason(exn), "42")
})

let () = runTests()
