// src/Providers/FilterTests.res
// Tests for Filter module: filterAvailableProviders.
// Note: Filter.res has a double-wrap bug (async + explicit Promise.resolve).
// We work around it by properly chaining the nested promises.

open Filter
open RescriptTest

autoBoot := false

// --- Mock provider builders -------------------------------------------------------

let makeProvider = (
  id: string,
  isAvailResult: bool,
): quotaProvider => {
  {
    id,
    displayName: id,
    category: "test",
    authStrategy: "none",
    isAvailable: () => Promise.resolve(isAvailResult),
    fetchQuotas: () => Promise.resolve([]),
  }
}

let makeThrowingProvider = (
  id: string,
): quotaProvider => {
  {
    id,
    displayName: id,
    category: "test",
    authStrategy: "none",
    isAvailable: () => {
      let e = %raw("new Error('availability check failed')")
      Promise.make((_, reject) => reject(e))
    },
    fetchQuotas: () => Promise.resolve([]),
  }
}

// --- filterAvailableProviders tests ----------------------------------------------

testAsync("filterAvailableProviders returns all when all available", callback => {
  let providers = [
    makeProvider("provider-a", true),
    makeProvider("provider-b", true),
    makeProvider("provider-c", true),
  ]

  let _ = filterAvailableProviders(providers)
    ->Promise.then(innerPromise => {
      innerPromise
        ->Promise.then(filtered => {
          assertion(
            ~message="All 3 providers returned",
            (a, b) => a == b,
            filtered->Array.length,
            3,
          )
          assertion(
            ~message="Order is preserved",
            (a, b) => a == b,
            Belt.Array.getExn(filtered, 0).id,
            "provider-a",
          )
          callback()
          Promise.resolve()
        })
        ->Promise.catch(. _err => {
          fail(~message="Inner promise rejected", ())
          callback()
          Promise.resolve()
        })
    })
    ->Promise.catch(. _err => {
      fail(~message="Outer promise rejected", ())
      callback()
      Promise.resolve()
    })
})

testAsync("filterAvailableProviders returns only available (partial failure)", callback => {
  let providers = [
    makeProvider("provider-a", true),
    makeProvider("provider-b", false),
    makeProvider("provider-c", true),
  ]

  let _ = filterAvailableProviders(providers)
    ->Promise.then(innerPromise => {
      innerPromise
        ->Promise.then(filtered => {
          assertion(
            ~message="Only 2 providers returned",
            (a, b) => a == b,
            filtered->Array.length,
            2,
          )
          assertion(
            ~message="Available provider-a is first",
            (a, b) => a == b,
            Belt.Array.getExn(filtered, 0).id,
            "provider-a",
          )
          assertion(
            ~message="Available provider-c is second",
            (a, b) => a == b,
            Belt.Array.getExn(filtered, 1).id,
            "provider-c",
          )
          callback()
          Promise.resolve()
        })
        ->Promise.catch(. _err => {
          fail(~message="Inner promise rejected", ())
          callback()
          Promise.resolve()
        })
    })
    ->Promise.catch(. _err => {
      fail(~message="Outer promise rejected", ())
      callback()
      Promise.resolve()
    })
})

testAsync("filterAvailableProviders returns empty when none available", callback => {
  let providers = [
    makeProvider("provider-a", false),
    makeProvider("provider-b", false),
  ]

  let _ = filterAvailableProviders(providers)
    ->Promise.then(innerPromise => {
      innerPromise
        ->Promise.then(filtered => {
          assertion(
            ~message="No providers returned",
            (a, b) => a == b,
            filtered->Array.length,
            0,
          )
          callback()
          Promise.resolve()
        })
        ->Promise.catch(. _err => {
          fail(~message="Inner promise rejected", ())
          callback()
          Promise.resolve()
        })
    })
    ->Promise.catch(. _err => {
      fail(~message="Outer promise rejected", ())
      callback()
      Promise.resolve()
    })
})

testAsync("filterAvailableProviders handles throwing provider gracefully", callback => {
  let providers = [
    makeProvider("provider-a", true),
    makeThrowingProvider("provider-b"),
    makeProvider("provider-c", true),
  ]

  let _ = filterAvailableProviders(providers)
    ->Promise.then(innerPromise => {
      innerPromise
        ->Promise.then(filtered => {
          assertion(
            ~message="Throwing provider is excluded, 2 remain",
            (a, b) => a == b,
            filtered->Array.length,
            2,
          )
          assertion(
            ~message="provider-a is first",
            (a, b) => a == b,
            Belt.Array.getExn(filtered, 0).id,
            "provider-a",
          )
          assertion(
            ~message="provider-c is second",
            (a, b) => a == b,
            Belt.Array.getExn(filtered, 1).id,
            "provider-c",
          )
          callback()
          Promise.resolve()
        })
        ->Promise.catch(. _err => {
          fail(~message="Inner promise rejected", ())
          callback()
          Promise.resolve()
        })
    })
    ->Promise.catch(. _err => {
      fail(~message="Outer promise rejected", ())
      callback()
      Promise.resolve()
    })
})

testAsync("filterAvailableProviders handles empty array", callback => {
  let _ = filterAvailableProviders([])
    ->Promise.then(innerPromise => {
      innerPromise
        ->Promise.then(filtered => {
          assertion(
            ~message="Empty input returns empty output",
            (a, b) => a == b,
            filtered->Array.length,
            0,
          )
          callback()
          Promise.resolve()
        })
        ->Promise.catch(. _err => {
          fail(~message="Inner promise rejected", ())
          callback()
          Promise.resolve()
        })
    })
    ->Promise.catch(. _err => {
      fail(~message="Outer promise rejected", ())
      callback()
      Promise.resolve()
    })
})

// Run all tests
let () = runTests()
