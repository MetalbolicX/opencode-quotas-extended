// ReportPipelineDepsTests.res — wiring test for ETTL injection and renderer/translator DI
// Verifies: pipeline uses renderer/translator from reportDeps; ETTL map is built from history.
open Domain
open RescriptTest

// ── FakeHistory helper — single module for all history scenarios ─────────────────
module FakeHistory = {
  type t = {
    getHistory: (string, float) => promise<array<historyPoint>>,
    append: (string, historyPoint) => promise<unit>,
    prune: float => promise<unit>,
    resetDetected: (string, historyPoint, float, option<float>) => bool,
  }
  let make = (~points: array<historyPoint>=[]): t => {
    let getHistory = (_id: string, _windowMs: float) => Promise.resolve(points)
    let append = (_id, _pt) => Promise.resolve()
    let prune = (_ms) => Promise.resolve()
    let resetDetected = (_id, _pt, _prev, _curr) => false
    {getHistory, append, prune, resetDetected}
  }
  let rejecting = (): t => {
    let getHistory = (_id: string, _windowMs: float) =>
      Promise.reject(%raw("new Error('simulated failure')"))
    let append = (_id, _pt) => Promise.resolve()
    let prune = (_ms) => Promise.resolve()
    let resetDetected = (_id, _pt, _prev, _curr) => false
    {getHistory, append, prune, resetDetected}
  }
}

// ── Quota / provider helpers ─────────────────────────────────────────────────────
let quota: quotaData = {
  id: "test-q", providerName: "Test", used: 50.0, limit: Some(100.0),
  unit: "requests", reset: None, window: #daily, info: None, modelId: None,
}

let quotaProvider: ReportPipeline.quotaProvider = {
  id: "test", displayName: "Test", category: "test", authStrategy: #api,
  isAvailable: () => Promise.resolve(true),
  fetchQuotas: () => Promise.resolve([quota]),
}

// ── Config / logger helpers ─────────────────────────────────────────────────────
let baseConfig = (): ReportPipeline.reportDeps_config => {
  displayMode: #table, disabled: [], aggregatedGroups: Dict.make(),
  historyMaxAgeHours: 24.0, predictionWindowMinutes: 60.0,
  predictionShortWindowMinutes: 5.0, showUnaggregated: false, progressBar: None,
}

let warnCalled: ref<bool> = ref(false)
let makeLogger = (): ReportPipeline.logger => {
  let debug = (_msg, ()) => ()
  let info = (_msg, ()) => ()
  let warn = (_msg, ()) => { warnCalled.contents = true }
  let error = (_msg, ()) => ()
  {debug, info, warn, error}
}

// ── Test data ──────────────────────────────────────────────────────────────────
let risingHistory: array<historyPoint> = [
  {timestamp: 1000.0, used: 10.0, limit: Some(100.0)},
  {timestamp: 2000.0, used: 20.0, limit: Some(100.0)},
  {timestamp: 3000.0, used: 30.0, limit: Some(100.0)},
  {timestamp: 4000.0, used: 40.0, limit: Some(100.0)},
  {timestamp: 5000.0, used: 50.0, limit: Some(100.0)},
]
let singlePointHistory: array<historyPoint> = [
  {timestamp: 5000.0, used: 50.0, limit: Some(100.0)},
]

let capturedRows: ref<array<quotaData>> = ref([])
let fakeRenderer = (): ReportPipeline.renderer => {
  {render: (rows, _ctx) => { capturedRows.contents = rows; "FAKE" }}
}

autoBoot := false

// ── ETTL wiring tests ──────────────────────────────────────────────────────────

testAsync("buildEttlMap: warm history produces finite ETTL", (testDone) => {
  let ettlMapP = ReportPipeline.buildEttlMap(
    (FakeHistory.make(~points=risingHistory) :> ReportPipeline.historyStore),
    5000.0, [quota], baseConfig(), makeLogger())
  let _ = ettlMapP->Promise.then(ettlMap => {
    switch Dict.get(ettlMap, "test-q") {
    | Some(v) => {
        assertion(~message="ETTL is finite", (a, _) => a, Float.isFinite(v), true)
        assertion(~message="ETTL is positive", (a, _) => a, v > 0.0, true)
      }
    | None => fail(~message="No ETTL entry for finite quota", ())
    }
    testDone(~planned=2, ())
    Promise.resolve()
  })->Promise.catch(exn => {
    fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
    testDone(~planned=0, ())
    Promise.resolve()
  })
})

testAsync("buildEttlMap: cold history (1 point) produces no entry", (testDone) => {
  let ettlMapP = ReportPipeline.buildEttlMap(
    (FakeHistory.make(~points=singlePointHistory) :> ReportPipeline.historyStore),
    5000.0, [quota], baseConfig(), makeLogger())
  let _ = ettlMapP->Promise.then(ettlMap => {
    switch Dict.get(ettlMap, "test-q") {
    | Some(_) => fail(~message="Unexpected ETTL entry for cold history", ())
    | None => assertion(~message="No ETTL entry for cold start", (a, _b) => a == a, true, true)
    }
    testDone(~planned=1, ())
    Promise.resolve()
  })->Promise.catch(exn => {
    fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
    testDone(~planned=0, ())
    Promise.resolve()
  })
})

testAsync("buildEttlMap: rejecting getHistory produces warn + no entry", (testDone) => {
  warnCalled.contents = false
  let ettlMapP = ReportPipeline.buildEttlMap(
    (FakeHistory.rejecting() :> ReportPipeline.historyStore),
    5000.0, [quota], baseConfig(), makeLogger())
  let _ = ettlMapP->Promise.then(ettlMap => {
    assertion(~message="warn was called", (a, _) => a, warnCalled.contents, true)
    switch Dict.get(ettlMap, "test-q") {
    | Some(_) => fail(~message="Unexpected entry despite rejected getHistory", ())
    | None => assertion(~message="No ETTL entry for rejected history", (a, _b) => a == a, true, true)
    }
    testDone(~planned=2, ())
    Promise.resolve()
  })->Promise.catch(exn => {
    fail(~message=`buildEttlMap threw unexpectedly: ${String.make(exn)}`, ())
    testDone(~planned=0, ())
    Promise.resolve()
  })
})

testAsync("buildEttlMap: read window is max of the two config values", (testDone) => {
  let capturedWindowMs: ref<option<float>> = ref(None)
  let store: ReportPipeline.historyStore = {
    append: (_id, _pt) => Promise.resolve(),
    getHistory: (_id, windowMs) => { capturedWindowMs.contents = Some(windowMs); Promise.resolve(risingHistory) },
    prune: (_ms) => Promise.resolve(),
    resetDetected: (_id, _pt, _prev, _curr) => false,
  }
  let cfg = { ...baseConfig(), historyMaxAgeHours: 1.0, predictionWindowMinutes: 120.0 }
  let ettlMapP = ReportPipeline.buildEttlMap(store, 5000.0, [quota], cfg, makeLogger())
  let _ = ettlMapP->Promise.then(_ettlMap => {
    switch capturedWindowMs.contents {
    | Some(w) => {
        let expected = 120.0 *. 60.0 *. 1000.0
        let diff = if w > expected { w -. expected } else { expected -. w }
        assertion(~message="windowMs is max of the two", (a, _) => a, diff < 1.0, true)
      }
    | None => fail(~message="getHistory was never called", ())
    }
    testDone(~planned=1, ())
    Promise.resolve()
  })->Promise.catch(exn => {
    fail(~message=`buildEttlMap threw: ${String.make(exn)}`, ())
    testDone(~planned=0, ())
    Promise.resolve()
  })
})

testAsync("reportQuotas: flat preservation when no user groups", (testDone) => {
  capturedRows.contents = []
  let deps: ReportPipeline.reportDeps = {
    credentialResolver: {get: (_id) => Promise.resolve(None)},
    httpClient: {request: (_url, _opts) => Promise.resolve()},
    registry: {list: () => [quotaProvider], get: (id) => if id === "test" { Some(quotaProvider) } else { None }},
    historyStore: (FakeHistory.make(~points=risingHistory) :> ReportPipeline.historyStore),
    config: {...baseConfig(), aggregatedGroups: Dict.make()},
    logger: makeLogger(),
    selectRenderer: (_mode) => fakeRenderer(),
    createI18nTranslator: (_) => {let t = (_key, _params) => ""; {t: t}},
  }
  let opts: ReportPipeline.reportOptions = {
    providerId: Some("test"), modelId: None, mode: #table, compact: None, color: None, now: Some(6000.0),
  }
  let _ = ReportPipeline.reportQuotas(deps, opts)
    ->Promise.then(_result => {
      assertion(~message="flat mode: rows length is 1", (a, b) => a == b, capturedRows.contents->Array.length, 1)
      testDone(~planned=1, ())
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      fail(~message=`Pipeline threw: ${String.make(exn)}`, ())
      testDone(~planned=0, ())
      Promise.resolve()
    })
})

let () = runTests()
