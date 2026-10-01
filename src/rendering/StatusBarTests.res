// src/rendering/StatusBarTests.res
// Regression tests for StatusBar.getStatus threshold semantics.
// Documented contract (module header + legacy TS): OK < 0.5 | WRN [0.5, 0.8) | ERR [0.8, ∞).
// The ported loop must return the FIRST matching gradient (legacy TS break-on-first),
// not the last one.

open StatusBar
open RescriptTest

autoBoot := false

let codeOf = (used: float, limit: option<float>): string => {
  let r = getStatus(used, limit)
  switch r.code {
  | OK => "OK"
  | WRN => "WRN"
  | ERR => "ERR"
  | UNK => "UNK"
  }
}

let codeOfWith = (gradients: array<gradient>, used: float, limit: option<float>): string => {
  let r = getStatus(used, limit, ~gradients)
  switch r.code {
  | OK => "OK"
  | WRN => "WRN"
  | ERR => "ERR"
  | UNK => "UNK"
  }
}

// --- Default gradients (0.5 green / 0.8 yellow / 1.0 red) ----------------------

test("zero usage is OK", () => {
  assertion(~message="used 0 is OK", (a, b) => a == b, codeOf(0.0, Some(100.0)), "OK")
})

test("unlimited (no limit) is OK with no ratio", () => {
  let r = getStatus(999.0, None)
  assertion(~message="no limit is OK", (a, b) => a == b, codeOf(999.0, None), "OK")
  assertion(~message="no limit has no ratio", (a, b) => a == b, r.ratio, None)
})

test("low usage stays OK (regression: was ERR for any use > 0)", () => {
  assertion(~message="used 4/100 is OK", (a, b) => a == b, codeOf(4.0, Some(100.0)), "OK")
  assertion(~message="used 49/100 is OK", (a, b) => a == b, codeOf(49.0, Some(100.0)), "OK")
})

test("medium usage is WRN in [0.5, 0.8)", () => {
  assertion(~message="used 50/100 is WRN", (a, b) => a == b, codeOf(50.0, Some(100.0)), "WRN")
  assertion(~message="used 79/100 is WRN", (a, b) => a == b, codeOf(79.0, Some(100.0)), "WRN")
})

test("high usage is ERR in [0.8, ∞)", () => {
  assertion(~message="used 80/100 is ERR", (a, b) => a == b, codeOf(80.0, Some(100.0)), "ERR")
  assertion(~message="used 100/100 is ERR", (a, b) => a == b, codeOf(100.0, Some(100.0)), "ERR")
  assertion(~message="over 100% is ERR", (a, b) => a == b, codeOf(120.0, Some(100.0)), "ERR")
})

test("ratio is returned alongside the code", () => {
  let r = getStatus(82.0, Some(100.0))
  assertion(~message="ratio is 0.82", (a, b) => a == b, r.ratio, Some(0.82))
})

// --- Custom gradients ------------------------------------------------------------

test("custom gradients pick the first matching band, not the last", () => {
  let custom = [
    { threshold: 0.3, color: "green" },
    { threshold: 0.6, color: "yellow" },
    { threshold: 1.0, color: "red" },
  ]
  // ratio 0.4 < 0.6 → yellow band (regression: last-match logic returned red)
  assertion(
    ~message="ratio 0.4 with custom bands is WRN (first match wins)",
    (a, b) => a == b,
    codeOfWith(custom, 40.0, Some(100.0)),
    "WRN",
  )
  // ratio 0.2 < 0.3 → green
  assertion(
    ~message="ratio 0.2 with custom bands is OK",
    (a, b) => a == b,
    codeOfWith(custom, 20.0, Some(100.0)),
    "OK",
  )
  // ratio >= last threshold → last gradient color
  assertion(
    ~message="ratio 1.0 with custom bands is ERR",
    (a, b) => a == b,
    codeOfWith(custom, 100.0, Some(100.0)),
    "ERR",
  )
})

test("empty gradients with nonzero usage is UNK", () => {
  assertion(
    ~message="no gradients and used > 0 is UNK",
    (a, b) => a == b,
    codeOfWith([], 50.0, Some(100.0)),
    "UNK",
  )
})

// Run all tests
let () = runTests()
