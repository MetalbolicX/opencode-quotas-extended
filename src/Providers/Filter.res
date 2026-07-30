// src/Providers/Filter.res
// Shared availability filter for CLI and plugin.
// Ported from src/adapters/providers/filter.ts.

// --- Local type declarations (mirrors port interfaces) -----------------------

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: string,
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<JSON.t>>,
}

// filterAvailableProviders filters providers that successfully returned true on isAvailable.
// Providers that throw during isAvailable are isolated and excluded.
let filterAvailableProviders = async (
  providers: array<quotaProvider>,
): Promise.t<array<quotaProvider>> => {
  let results = await Promise.all(
    providers->Array.map(p => {
      p.isAvailable()->Promise.then(isAvail => {
        Promise.resolve((p, isAvail))
      })->Promise.catch(. _err => {
        Promise.resolve((p, false))
      })
    })
  )

  let filtered = []
  results->Array.forEach(((prov, isAvail)) => {
    if isAvail {
      filtered->Array.push(prov)->ignore
    }
  })
  Promise.resolve(filtered)
}
