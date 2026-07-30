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
let filterAvailableProviders = (
  providers: array<quotaProvider>,
): Promise.t<array<quotaProvider>> => {
  let collected: array<quotaProvider> = []
  let pushIfAvail = (p: quotaProvider, isAvail: bool): Promise.t<unit> => {
    if isAvail {
      collected->Array.push(p)->ignore
    }
    Promise.resolve()
  }
  let chain: Promise.t<unit> = Promise.resolve()
  let finalChain = providers->Array.reduce(chain, (acc, p) => {
    (acc->Promise.then(_ =>
      p.isAvailable()
      ->Promise.then(isAvail => pushIfAvail(p, isAvail))
      ->Promise.catch(. _err => pushIfAvail(p, false))
    ): Promise.t<unit>)
  })
  finalChain->Promise.then(. _ => Promise.resolve(collected))
}
