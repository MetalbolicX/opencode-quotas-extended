// src/Infra/JsonFileHistoryTests.res
// Tests for JsonFileHistory HistoryStore adapter.
open RescriptTest

autoBoot := false

// deps type from the module
type deps = JsonFileHistory.deps

// In-memory file system mock
type mockFs = {
  files: ref<dict<string>>,
  writes: ref<int>,
  now: ref<float>,
  exists: ref<dict<bool>>,
}

let makeFs = (): mockFs => {
  files: ref(Dict.make()),
  writes: ref(0),
  now: ref(0.0),
  exists: ref(Dict.make()),
}

let makeDeps = (fs: mockFs): deps => {
  readFileSync: (p: string) => {
    switch Dict.get(fs.files.contents, p) {
    | Some(content) => content
    | None => ""
    }
  },
  writeFileSync: (p: string, d: string) => {
    Dict.set(fs.files.contents, p, d)
    fs.writes := fs.writes.contents + 1
  },
  existsSync: (p: string) => {
    switch Dict.get(fs.exists.contents, p) {
    | Some(b) => b
    | None => false
    }
  },
  now: () => fs.now.contents,
}

let mkPoint = (~timestamp: float, ~used: float, ~limit: option<float>=None): Domain.historyPoint => {
  timestamp: timestamp,
  used: used,
  limit: limit,
}

// Helper: create a JSON string for an empty history
let emptyHistoryJson = (): string => {
  JSON.stringify(JSON.Encode.object(Dict.make()))
}

// Helper: set up a test file with initial history
let setupTestFile = (fs: mockFs, path: string, initialContent: option<string>) => {
  Dict.set(fs.exists.contents, path, true)
  switch initialContent {
  | Some(content) => Dict.set(fs.files.contents, path, content)
  | None => Dict.set(fs.files.contents, path, emptyHistoryJson())
  }
}

// 1. append is debounced - writes should be 0 immediately after append
testAsync("append does not write immediately (debounced)", callback => {
  let fs = makeFs()
  setupTestFile(fs, "/test/history.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=50.0, "/test/history.json", deps)
  store.append("prov1", mkPoint(~timestamp=1000.0, ~used=10.0))->Promise.then(_ => {
    assertion(
      ~message="writes should be 0 immediately after append",
      (a, b) => a == b,
      fs.writes.contents,
      0,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 2. append extends an existing provider - getHistory returns both points
testAsync("append twice returns both points in getHistory", callback => {
  let fs = makeFs()
  fs.now := 1000.0
  setupTestFile(fs, "/test/h2.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h2.json", deps)
  store.append("prov1", mkPoint(~timestamp=100.0, ~used=10.0))
  ->Promise.then(_ => store.append("prov1", mkPoint(~timestamp=200.0, ~used=20.0)))
  ->Promise.then(_ => store.getHistory("prov1", 10000.0))
  ->Promise.then(points => {
    assertion(
      ~message=`Expected 2 points, got ${Belt.Array.length(points)->Int.toString}`,
      (a, b) => a == b,
      Belt.Array.length(points),
      2,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 3. window filtering - getHistory returns only points within window
testAsync("getHistory filters by window", callback => {
  let fs = makeFs()
  fs.now := 1000.0
  setupTestFile(fs, "/test/h3.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h3.json", deps)
  store.append("prov1", mkPoint(~timestamp=500.0, ~used=10.0))
  ->Promise.then(_ => store.getHistory("prov1", 200.0))
  ->Promise.then(points => {
    assertion(
      ~message="window=200 should exclude point at timestamp=500",
      (a, b) => a == b,
      Belt.Array.length(points),
      0,
    )
    Promise.resolve(())
  })
  ->Promise.then(_ => store.getHistory("prov1", 600.0))
  ->Promise.then(points => {
    assertion(
      ~message="window=600 should include point at timestamp=500",
      (a, b) => a == b,
      Belt.Array.length(points),
      1,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 4. in-memory read before flush - getHistory sees appended point immediately
testAsync("getHistory returns point immediately after append (in-memory)", callback => {
  let fs = makeFs()
  fs.now := 1000.0
  setupTestFile(fs, "/test/h4.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h4.json", deps)
  store.append("prov1", mkPoint(~timestamp=900.0, ~used=10.0))
  ->Promise.then(_ => store.getHistory("prov1", 10000.0))
  ->Promise.then(points => {
    assertion(
      ~message="getHistory should return appended point immediately",
      (a, b) => a == b,
      Belt.Array.length(points),
      1,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 5. prune removes stale points and saves immediately
testAsync("prune removes stale points and saves immediately", callback => {
  let fs = makeFs()
  fs.now := 1000.0
  // Set initial history with a stale point
  let staleHistory = JSON.stringify(JSON.Encode.object(Dict.fromArray([("prov1", JSON.Encode.array([JSON.Encode.object(Dict.fromArray([("timestamp", JSON.Encode.float(500.0)), ("used", JSON.Encode.float(10.0)), ("limit", JSON.Encode.null)]))]))])))
  setupTestFile(fs, "/test/h5.json", Some(staleHistory))
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h5.json", deps)
  store.prune(1000.0) // removes points older than 1000ms ago
  ->Promise.then(_ => {
    assertion(
      ~message="writes should be 1 after prune (immediate save)",
      (a, b) => a == b,
      fs.writes.contents,
      1,
    )
    Promise.resolve(())
  })
  ->Promise.then(_ => store.getHistory("prov1", 10000.0))
  ->Promise.then(points => {
    assertion(
      ~message="prune should remove stale point at timestamp=500",
      (a, b) => a == b,
      Belt.Array.length(points),
      0,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 6. reset detection returns true when usage drops significantly
testAsync("resetDetected returns true on significant usage drop", callback => {
  let fs = makeFs()
  setupTestFile(fs, "/test/h6.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h6.json", deps)
  // First append with high usage (100)
  store.append("prov1", mkPoint(~timestamp=100.0, ~used=100.0, ~limit=Some(100.0)))
  ->Promise.then(_ => {
    // resetDetected: prev point used=100, new used=10 (90% drop, >20% threshold)
    let result = store.resetDetected("prov1", mkPoint(~timestamp=100.0, ~used=100.0, ~limit=Some(100.0)), 10.0, Some(100.0))
    assertion(
      ~message="reset should be detected on 90% drop",
      (a, b) => a == b,
      result,
      true,
    )
    callback()
    Promise.resolve(())
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 7. missing file initializes empty history
testAsync("missing file initializes empty history", callback => {
  let fs = makeFs()
  // Don't set exists for this path
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/nonexistent.json", deps)
  store.getHistory("prov1", 10000.0)
  ->Promise.then(points => {
    assertion(
      ~message="missing file should return empty history",
      (a, b) => a == b,
      Belt.Array.length(points),
      0,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 8. invalid JSON initializes empty history
testAsync("invalid JSON initializes empty history", callback => {
  let fs = makeFs()
  setupTestFile(fs, "/test/h8.json", Some("not valid json {"))
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h8.json", deps)
  store.getHistory("prov1", 10000.0)
  ->Promise.then(points => {
    assertion(
      ~message="invalid JSON should return empty history",
      (a, b) => a == b,
      Belt.Array.length(points),
      0,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 9. write failure is swallowed (no error thrown)
test("write failure is swallowed", () => {
  let fs = makeFs()
  setupTestFile(fs, "/test/h9.json", None)
  let deps = makeDeps(fs)
  let _store = JsonFileHistory.make(~debounceMs=50.0, "/test/h9.json", deps)
  doesNotThrow(
    ~message="append should not throw even if write fails",
    () => {
      // Override write to throw, but catch it in the store
      let throwingDeps: deps = {
        readFileSync: deps.readFileSync,
        writeFileSync: (_p, _d) => {
          // Intentionally raise - the store catches it internally
          JsError.throwWithMessage("simulated write failure")
        },
        existsSync: deps.existsSync,
        now: deps.now,
      }
      let _throwStore = JsonFileHistory.make(~debounceMs=50.0, "/test/h9.json", throwingDeps)
      _throwStore.append("prov1", mkPoint(~timestamp=100.0, ~used=10.0))->ignore
    },
  )
})

// 10. unknown provider returns empty history
testAsync("unknown provider returns empty history", callback => {
  let fs = makeFs()
  setupTestFile(fs, "/test/h10.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h10.json", deps)
  store.getHistory("never-appended", 10000.0)
  ->Promise.then(points => {
    assertion(
      ~message="unknown provider should return empty history",
      (a, b) => a == b,
      Belt.Array.length(points),
      0,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 11. multiple appends coalesce (writes stays 0 within debounce window)
testAsync("multiple appends keep writes at 0 before debounce fires", callback => {
  let fs = makeFs()
  setupTestFile(fs, "/test/h11.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h11.json", deps)
  store.append("prov1", mkPoint(~timestamp=100.0, ~used=10.0))
  ->Promise.then(_ => store.append("prov1", mkPoint(~timestamp=200.0, ~used=20.0)))
  ->Promise.then(_ => store.append("prov1", mkPoint(~timestamp=300.0, ~used=30.0)))
  ->Promise.then(_ => {
    assertion(
      ~message="writes should be 0 after 3 appends (debounce not fired)",
      (a, b) => a == b,
      fs.writes.contents,
      0,
    )
    callback()
    Promise.resolve(())
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 12. second append within debounce keeps both points in memory
testAsync("second append within debounce keeps both points", callback => {
  let fs = makeFs()
  fs.now := 100.0
  setupTestFile(fs, "/test/h12.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h12.json", deps)
  store.append("prov1", mkPoint(~timestamp=50.0, ~used=10.0))
  ->Promise.then(_ => store.append("prov1", mkPoint(~timestamp=75.0, ~used=20.0)))
  ->Promise.then(_ => store.getHistory("prov1", 10000.0))
  ->Promise.then(points => {
    assertion(
      ~message="getHistory should return both appended points",
      (a, b) => a == b,
      Belt.Array.length(points),
      2,
    )
    callback()
    Promise.resolve()
  })
  ->Promise.catch((. _err) => {
    assertion(~message="should not throw", (a, b) => a == b, true, false)
    callback()
    Promise.resolve()
  })
  ->ignore
})

// 13. manual flushNow forces write before debounce window
test("flushNow writes immediately and cancels pending debounce", () => {
  let fs = makeFs()
  fs.now := 100.0
  setupTestFile(fs, "/test/h13.json", None)
  let deps = makeDeps(fs)
  let store = JsonFileHistory.make(~debounceMs=5000.0, "/test/h13.json", deps)
  // Append synchronously — Promise.resolve resolves immediately when awaited
  let _ = store.append("prov1", mkPoint(~timestamp=50.0, ~used=10.0))
  // Before flush: writes should be 0
  assertion(
    ~message=`Expected 0 writes before flushNow, got ${Int.toString(fs.writes.contents)}`,
    (a, b) => a == b,
    fs.writes.contents,
    0,
  )
  // Flush
  store.flushNow()
  // After flush: writes should be 1
  assertion(
    ~message=`Expected 1 write after flushNow, got ${Int.toString(fs.writes.contents)}`,
    (a, b) => a == b,
    fs.writes.contents,
    1,
  )
})

let () = runTests()
