// ReportPipelineDepsTests.res — wiring test for renderer/translator injection
// TDD-LIGHT: write test FIRST (RED), then inject deps via reportDeps
// Verifies: pipeline uses renderer/translator from reportDeps (not direct adapter imports)

open Domain
open RescriptTest

module FakeRenderer = {
  let wasCalled: ref<bool> = ref(false)
  let capturedRows: ref<array<quotaData>> = ref([])

  type renderer = {
    render: (array<quotaData>, ReportPipeline.renderContext) => string
  }

  let make = (): renderer => {
    wasCalled.contents = false
    capturedRows.contents = []
    {
      render: (rows, _ctx) => {
        wasCalled.contents = true
        capturedRows.contents = rows
        "FAKE-RENDERED-OUTPUT"
      },
    }
  }
}

module FakeTranslator = {
  let wasUsed: ref<bool> = ref(false)
  let keys: ref<array<string>> = ref([])

  type translator = {
    t: (string, option<dict<string>>) => string
  }

  let make = (): translator => {
    wasUsed.contents = false
    keys.contents = []
    {
      t: (key, _params) => {
        wasUsed.contents = true
        keys.contents->Array.push(key)->ignore
        `ft:${key}`
      },
    }
  }
}

let fakeSelectRenderer = (_mode: renderMode): ReportPipeline.renderer =>
  (FakeRenderer.make() :> ReportPipeline.renderer)

let fakeCreateI18nTranslator = (_catalog: 'a): ReportPipeline.translator =>
  (FakeTranslator.make() :> ReportPipeline.translator)

let stubQuota: quotaData = {
  id: "stub/req",
  providerName: "Stub",
  used: 42.0,
  limit: Some(100.0),
  unit: "requests",
  reset: None,
  window: #daily,
  info: None,
  modelId: None,
}

let stubProvider: ReportPipeline.quotaProvider = {
  id: "stub",
  displayName: "Stub Provider",
  category: "test",
  authStrategy: #api,
  isAvailable: () => Promise.resolve(true),
  fetchQuotas: () => Promise.resolve([stubQuota]),
}

let makeNoopHistory = (): ReportPipeline.historyStore => {
  let append = (_id, _pt) => Promise.resolve()
  let getHistory = (_id, _ms) => Promise.resolve([])
  let prune = (_ms) => Promise.resolve()
  let resetDetected = (_id, _pt, _prev, _curr) => false
  {append, getHistory, prune, resetDetected}
}

let makeNoopLogger = (): ReportPipeline.logger => {
  let debug = (_msg, ()) => ()
  let info = (_msg, ()) => ()
  let warn = (_msg, ()) => ()
  let error = (_msg, ()) => ()
  {debug, info, warn, error}
}

autoBoot := false

// NOTE: This test requires reportDeps to have selectRenderer and createI18nTranslator fields.
// When those fields are absent (current code), the test FAILS to compile — that's RED.
testAsync("renderer and translator are injected via reportDeps", (testDone) => {
  let deps: ReportPipeline.reportDeps = {
    credentialResolver: {
      get: (_id) => Promise.resolve(None),
    },
    httpClient: {
      request: (_url, _opts) => Promise.resolve(),
    },
    registry: {
      list: () => [stubProvider],
      get: (id) => if id === "stub" { Some(stubProvider) } else { None },
    },
    historyStore: makeNoopHistory(),
    config: {
      displayMode: #table,
      disabled: [],
      aggregatedGroups: Dict.make(),
      historyMaxAgeHours: 24.0,
      predictionWindowMinutes: 60.0,
      predictionShortWindowMinutes: 5.0,
      showUnaggregated: true,
      progressBar: None,
    },
    logger: makeNoopLogger(),
    selectRenderer: fakeSelectRenderer,
    createI18nTranslator: fakeCreateI18nTranslator,
  }

  let opts: ReportPipeline.reportOptions = {
    providerId: Some("stub"),
    modelId: None,
    mode: #table,
    compact: None,
    color: None,
    now: Some(1000.0),
  }

  // reportQuotas returns promise<promise<X>> — unwrap via nested Promise.then chain
  let _ = ReportPipeline.reportQuotas(deps, opts)
    ->Promise.then(innerPromise => {
      innerPromise
      ->Promise.then(result => {
        if !FakeRenderer.wasCalled.contents {
          fail(~message="Fake renderer was NOT invoked", ())
        } else {
          assertion((a, b) => a == b, result.rendered, "FAKE-RENDERED-OUTPUT")
        }
        if !FakeTranslator.wasUsed.contents {
          fail(~message="Fake translator was NOT used", ())
        } else {
          assertion(
            (a, b) => a == b,
            FakeTranslator.keys.contents->Array.length > 0,
            true,
          )
        }
        testDone(~planned=4, ())
        Promise.resolve()
      })
      ->Promise.catch(exn => {
        fail(~message=`Pipeline threw: ${String.make(exn)}`, ())
        testDone(~planned=0, ())
        Promise.resolve()
      })
    })
})

// ── ETTL wiring tests ──────────────────────────────────────────────────────────

// Fake history store that returns configurable points
module FakeHistoryWithPoints = {
  type t = {
    getHistory: (string, float) => promise<array<Domain.historyPoint>>,
    append: (string, Domain.historyPoint) => promise<unit>,
    prune: float => promise<unit>,
    resetDetected: (string, Domain.historyPoint, float, option<float>) => bool,
  }

  let make = (~points: array<Domain.historyPoint>): t => {
    let getHistory = (_id: string, _windowMs: float) => Promise.resolve(points)
    let append = (_id, _pt) => Promise.resolve()
    let prune = (_ms) => Promise.resolve()
    let resetDetected = (_id, _pt, _prev, _curr) => false
    {getHistory, append, prune, resetDetected}
  }
}

module FakeHistoryRejecting = {
  type t = {
    getHistory: (string, float) => promise<array<Domain.historyPoint>>,
    append: (string, Domain.historyPoint) => promise<unit>,
    prune: float => promise<unit>,
    resetDetected: (string, Domain.historyPoint, float, option<float>) => bool,
  }

  let make = (): t => {
    let getHistory = (_id: string, _windowMs: float) =>
      Promise.reject(%raw("new Error('simulated failure')"))
    let append = (_id, _pt) => Promise.resolve()
    let prune = (_ms) => Promise.resolve()
    let resetDetected = (_id, _pt, _prev, _curr) => false
    {getHistory, append, prune, resetDetected}
  }
}

// Quota with finite limit (eligible)
let finiteQuota: quotaData = {
  id: "finite-q",
  providerName: "test",
  used: 50.0,
  limit: Some(100.0),
  unit: "requests",
  reset: None,
  window: #daily,
  info: None,
  modelId: None,
}

// Quota with no limit (not eligible)
let unlimitedQuota: quotaData = {
  id: "unlimited-q",
  providerName: "test",
  used: 50.0,
  limit: None,
  unit: "requests",
  reset: None,
  window: #daily,
  info: None,
  modelId: None,
}

// Rising history: 5 points over 30min at 50% burn rate
let risingHistory: array<Domain.historyPoint> = [
  {timestamp: 1000.0, used: 10.0, limit: Some(100.0)},
  {timestamp: 2000.0, used: 20.0, limit: Some(100.0)},
  {timestamp: 3000.0, used: 30.0, limit: Some(100.0)},
  {timestamp: 4000.0, used: 40.0, limit: Some(100.0)},
  {timestamp: 5000.0, used: 50.0, limit: Some(100.0)},
]

// Single-point history: cold start
let singlePointHistory: array<Domain.historyPoint> = [
  {timestamp: 5000.0, used: 50.0, limit: Some(100.0)},
]

// Provider that returns the finite quota
let finiteQuotaProvider: ReportPipeline.quotaProvider = {
  id: "finite-test",
  displayName: "Finite Test",
  category: "test",
  authStrategy: #api,
  isAvailable: () => Promise.resolve(true),
  fetchQuotas: () => Promise.resolve([finiteQuota]),
}

// Provider that returns the unlimited quota
let unlimitedQuotaProvider: ReportPipeline.quotaProvider = {
  id: "unlimited-test",
  displayName: "Unlimited Test",
  category: "test",
  authStrategy: #api,
  isAvailable: () => Promise.resolve(true),
  fetchQuotas: () => Promise.resolve([unlimitedQuota]),
}

let warnCalled: ref<bool> = ref(false)
let warnMessages: ref<array<string>> = ref([])

let capturingLogger = (): ReportPipeline.logger => {
  let debug = (_msg, ()) => ()
  let info = (_msg, ()) => ()
  let warn = (msg, ()) => {
    warnCalled.contents = true
    warnMessages.contents->Array.push(msg)->ignore
  }
  let error = (_msg, ()) => ()
  {debug, info, warn, error}
}

let baseConfig = (): ReportPipeline.reportDeps_config => {
  displayMode: #table,
  disabled: [],
  aggregatedGroups: Dict.make(),
  historyMaxAgeHours: 24.0,
  predictionWindowMinutes: 60.0,
  predictionShortWindowMinutes: 5.0,
  showUnaggregated: false,
  progressBar: None,
}

testAsync("buildEttlMap: warm history produces finite ETTL", (testDone) => {
  let store = FakeHistoryWithPoints.make(~points=risingHistory)
  let cfg = baseConfig()
  let log = capturingLogger()
  warnCalled.contents = false
  warnMessages.contents = []

  let getHistoryCallCount: ref<int> = ref(0)
  let countingStore: ReportPipeline.historyStore = {
    append: (_id, _pt) => Promise.resolve(),
    getHistory: (id, windowMs) => {
      getHistoryCallCount.contents = getHistoryCallCount.contents + 1
      store.getHistory(id, windowMs)
    },
    prune: (_ms) => Promise.resolve(),
    resetDetected: (_id, _pt, _prev, _curr) => false,
  }

  let ettlMapP = ReportPipeline.buildEttlMap(
    countingStore,
    5000.0, // now
    [finiteQuota],
    cfg,
    log,
  )

  let _ = ettlMapP
    ->Promise.then(ettlMap => {
      // ETTL should be finite positive
      let entry = Dict.get(ettlMap, "finite-q")
      switch entry {
      | Some(v) => {
          assertion(~message="ETTL is finite", (a, _b) => a == true, Float.isFinite(v), true)
          assertion(~message="ETTL is positive", (a, _b) => a == true, v > 0.0, true)
        }
      | None => fail(~message="No ETTL entry for finite quota", ())
      }
      testDone(~planned=3, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

testAsync("buildEttlMap: cold history (1 point) produces no entry", (testDone) => {
  let store = FakeHistoryWithPoints.make(~points=singlePointHistory)
  let cfg = baseConfig()
  let log = capturingLogger()

  let ettlMapP = ReportPipeline.buildEttlMap(
    (store :> ReportPipeline.historyStore),
    5000.0,
    [finiteQuota],
    cfg,
    log,
  )

  let _ = ettlMapP
    ->Promise.then(ettlMap => {
      // Single point → no ETTL entry (cold start)
      let entry = Dict.get(ettlMap, "finite-q")
      switch entry {
      | Some(_) => fail(~message="Unexpected ETTL entry for cold history", ())
      | None => assertion(~message="No ETTL entry for cold start", (a, _b) => a == a, true, true)
      }
      testDone(~planned=1, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

testAsync("buildEttlMap: eligibility requires finite positive limit", (testDone) => {
  let store = FakeHistoryWithPoints.make(~points=risingHistory)
  let cfg = baseConfig()
  let log = capturingLogger()

  let ettlMapP = ReportPipeline.buildEttlMap(
    (store :> ReportPipeline.historyStore),
    5000.0,
    [unlimitedQuota], // no limit → not eligible
    cfg,
    log,
  )

  let _ = ettlMapP
    ->Promise.then(ettlMap => {
      let entry = Dict.get(ettlMap, "unlimited-q")
      switch entry {
      | Some(_) => fail(~message="Unexpected ETTL entry for unlimited quota", ())
      | None => assertion(~message="No ETTL entry for unlimited quota", (a, _b) => a == a, true, true)
      }
      testDone(~planned=1, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

testAsync("buildEttlMap: rejecting getHistory produces warn + no entry", (testDone) => {
  let store = FakeHistoryRejecting.make()
  let cfg = baseConfig()
  let log = capturingLogger()
  warnCalled.contents = false
  warnMessages.contents = []

  let ettlMapP = ReportPipeline.buildEttlMap(
    (store :> ReportPipeline.historyStore),
    5000.0,
    [finiteQuota],
    cfg,
    log,
  )

  let _ = ettlMapP
    ->Promise.then(ettlMap => {
      // Should have warned
      assertion(~message="warn was called", (a, _b) => a == a, warnCalled.contents, true)
      // Should have no entry (corrupt history)
      let entry = Dict.get(ettlMap, "finite-q")
      switch entry {
      | Some(_) => fail(~message="Unexpected entry despite rejected getHistory", ())
      | None => assertion(~message="No ETTL entry for rejected history", (a, _b) => a == a, true, true)
      }
      testDone(~planned=2, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`buildEttlMap threw unexpectedly: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

testAsync("buildEttlMap: read window is max(historyMaxAgeHours, predictionWindowMinutes)", (testDone) => {
  let capturedWindowMs: ref<option<float>> = ref(None)
  let store: ReportPipeline.historyStore = {
    append: (_id, _pt) => Promise.resolve(),
    getHistory: (id, windowMs) => {
      capturedWindowMs.contents = Some(windowMs)
      Promise.resolve(risingHistory)
    },
    prune: (_ms) => Promise.resolve(),
    resetDetected: (_id, _pt, _prev, _curr) => false,
  }
  let cfg = {
    ...baseConfig(),
    historyMaxAgeHours: 1.0, // 1h = 3.6e6 ms
    predictionWindowMinutes: 120.0, // 120min = 7.2e6 ms → larger → used
  }
  let log = capturingLogger()

  let ettlMapP = ReportPipeline.buildEttlMap(store, 5000.0, [finiteQuota], cfg, log)

  let _ = ettlMapP
    ->Promise.then(ettlMap => {
      // predictionWindowMinutes (120*60*1000=7.2e6) > historyMaxAgeHours (1*3600000=3.6e6)
      // so window should be 7.2e6
      switch capturedWindowMs.contents {
      | Some(w) => {
          let expected = 120.0 *. 60.0 *. 1000.0
          let diff = if w > expected { w -. expected } else { expected -. w }
          assertion(~message="windowMs is max of the two", (a, _b) => a == true, diff < 1.0, true)
        }
      | None => fail(~message="getHistory was never called", ())
      }
      testDone(~planned=1, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

testAsync("buildEttlMap: duplicate ids → later wins", (testDone) => {
  // Two quotas with same id
  let q1: quotaData = {...finiteQuota, id: "dup-id", used: 30.0}
  let q2: quotaData = {...finiteQuota, id: "dup-id", used: 50.0}
  let store = FakeHistoryWithPoints.make(~points=risingHistory)
  let cfg = baseConfig()
  let log = capturingLogger()

  let ettlMapP = ReportPipeline.buildEttlMap((store :> ReportPipeline.historyStore), 5000.0, [q1, q2], cfg, log)

  let _ = ettlMapP
    ->Promise.then(ettlMap => {
      // Only one entry for "dup-id"
      let allKeys = Dict.keysToArray(ettlMap)
      let dupCount = allKeys->Array.filter(k => k === "dup-id")->Array.length
      assertion(~message="only one entry for duplicate id", (a, _b) => a == 1, dupCount, 1)
      testDone(~planned=1, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

// Fake renderer to capture display rows
let capturedRows: ref<array<quotaData>> = ref([])
let fakeRenderer = (): ReportPipeline.renderer => {
  {
    render: (rows, _ctx) => {
      capturedRows.contents = rows
      "FAKE"
    },
  }
}

testAsync("reportQuotas: flat preservation when no user groups", (testDone) => {
  capturedRows.contents = []
  let deps: ReportPipeline.reportDeps = {
    credentialResolver: {get: (_id) => Promise.resolve(None)},
    httpClient: {request: (_url, _opts) => Promise.resolve()},
    registry: {
      list: () => [finiteQuotaProvider],
      get: (id) => if id === "finite-test" { Some(finiteQuotaProvider) } else { None },
    },
    historyStore: (FakeHistoryWithPoints.make(~points=risingHistory) :> ReportPipeline.historyStore),
    config: {
      ...baseConfig(),
      aggregatedGroups: Dict.make(), // no user groups
    },
    logger: capturingLogger(),
    selectRenderer: (_mode) => fakeRenderer(),
    createI18nTranslator: (_) => {
      let t = (_key, _params) => ""
      {t: t}
    },
  }
  let opts: ReportPipeline.reportOptions = {
    providerId: Some("finite-test"),
    modelId: None,
    mode: #table,
    compact: None,
    color: None,
    now: Some(6000.0),
  }

  let _ = ReportPipeline.reportQuotas(deps, opts)
    ->Promise.then(p2 => {
      p2
        ->Promise.then(result => {
          // With no user groups: rows should be allData (flat)
          assertion(
            ~message="flat mode: rows are flat allData",
            (a, b) => a == b,
            capturedRows.contents->Array.length,
            1,
          )
          testDone(~planned=1, ())
          Promise.resolve()
        })
        ->Promise.catch(exn => {
          fail(~message=`Inner pipeline threw: ${String.make(exn)}`, ())
          testDone(~planned=0, ())
          Promise.resolve()
        })
    })
    ->Promise.catch(exn => {
      fail(~message=`Pipeline threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})
