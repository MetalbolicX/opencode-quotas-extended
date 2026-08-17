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
