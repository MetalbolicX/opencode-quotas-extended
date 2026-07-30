// Provider registry — wires all 8 provider creators into a single registry.

type providerRegistry = {
  ids: unit => array<string>,
  get: string => option<Provider.quotaProvider>,
  all: unit => array<Provider.quotaProvider>,
}

let allProviders: unit => array<Provider.quotaProvider>

let buildDefaultRegistry: unit => providerRegistry

type deps = {
  credentialResolver: option<string>,
  httpClient: option<string>,
}

let buildDefaultRegistryWith: deps => providerRegistry
