// src/ports/LoggerTests.res
// Tests for Logger port — verifies noopLogger interface compliance.
// The Logger port is declared in Logger.resi (interface-only) with the canonical
// implementation provided by FetchHttp.noopLogger (used by all providers).
// This test validates the interface contract: all four methods are callable,
// return unit (no-ops), and accept optional meta without throwing.
open RescriptTest
open FetchHttp

autoBoot := false

// L1: noopLogger is accessible (exported from FetchHttp module)
test("L1: noopLogger is accessible from FetchHttp", () => {
  doesNotThrow(
    ~message="noopLogger should be accessible",
    () => {
      let _ = noopLogger
    },
  )
})

// L2–L5: All four methods are callable no-ops
test("L2: warn is callable and returns unit (no-op)", () => {
  doesNotThrow(
    ~message="noopLogger.warn should not throw",
    () => {
      let _ = noopLogger.warn("test-event", None)
    },
  )
})

test("L3: debug is callable and returns unit (no-op)", () => {
  doesNotThrow(
    ~message="noopLogger.debug should not throw",
    () => {
      let _ = noopLogger.debug("test-event", None)
    },
  )
})

test("L4: info is callable and returns unit (no-op)", () => {
  doesNotThrow(
    ~message="noopLogger.info should not throw",
    () => {
      let _ = noopLogger.info("test-event", None)
    },
  )
})

test("L5: error is callable and returns unit (no-op)", () => {
  doesNotThrow(
    ~message="noopLogger.error should not throw",
    () => {
      let _ = noopLogger.error("test-event", None)
    },
  )
})

// L6–L9: Methods accept optional meta parameter without throwing
test("L6: warn accepts optional meta None without throwing", () => {
  doesNotThrow(
    ~message="warn with None meta should not throw",
    () => {
      let _ = noopLogger.warn("event", None)
    },
  )
})

test("L7: debug accepts optional meta None without throwing", () => {
  doesNotThrow(
    ~message="debug with None meta should not throw",
    () => {
      let _ = noopLogger.debug("event", None)
    },
  )
})

test("L8: info accepts optional meta None without throwing", () => {
  doesNotThrow(
    ~message="info with None meta should not throw",
    () => {
      let _ = noopLogger.info("event", None)
    },
  )
})

test("L9: error accepts optional meta None without throwing", () => {
  doesNotThrow(
    ~message="error with None meta should not throw",
    () => {
      let _ = noopLogger.error("event", None)
    },
  )
})

// L10: Multiple sequential calls are idempotent (no side-effects)
test("L10: warn is idempotent — multiple calls without side-effects", () => {
  doesNotThrow(
    ~message="multiple warn calls should not throw",
    () => {
      let _ = noopLogger.warn("event-1", None)
      let _ = noopLogger.warn("event-2", None)
      let _ = noopLogger.warn("event-3", None)
    },
  )
})

// L11: All four methods can be called in sequence without throwing
test("L11: all four logger methods callable in sequence", () => {
  doesNotThrow(
    ~message="all four methods in sequence should not throw",
    () => {
      let _ = noopLogger.debug("dbg", None)
      let _ = noopLogger.info("inf", None)
      let _ = noopLogger.warn("wrn", None)
      let _ = noopLogger.error("err", None)
    },
  )
})

let () = runTests()
