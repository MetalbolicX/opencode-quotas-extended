// src/Providers/Registry.res
// Provider registry — wires all 8 provider creators into a single registry.
// Mirrors src/adapters/providers/registry.ts (TS version retained for rollback safety).

// --- Registry type ------------------------------------------------------------

type providerRegistry = {
  ids: unit => array<string>,
  get: string => option<Provider.quotaProvider>,
  all: unit => array<Provider.quotaProvider>,
}

// --- All provider creators -----------------------------------------------------

let allProviders = (): array<Provider.quotaProvider> => [
  OpenAI.createOpenAIProvider(),
  Zen.createZenProvider(),
  Go.createGoProvider(),
  Zai.createZaiProvider(),
  Kimi.createKimiProvider(),
  Minimax.createMinimaxProvider(),
  Anthropic.createAnthropicProvider(),
  Gemini.createGeminiProvider(),
]

// --- Default registry builder --------------------------------------------------

let buildDefaultRegistry = (): providerRegistry => {
  let providers = allProviders()
  {
    ids: () => providers->Array.map(p => p.id),
    get: (id: string) => Belt.Array.getBy(providers, p => p.id == id),
    all: () => providers,
  }
}

// --- Injected registry builder -------------------------------------------------
// Wiring point for credential resolver + http client. Currently returns the same
// providers as buildDefaultRegistry (the providers themselves hardcode their
// CredentialResolver.resolve call). The signature documents the intended
// dependency-injection surface so future provider refactors can thread through
// the resolver + http client without changing this call site.

type deps = {
  credentialResolver: option<string>,
  httpClient: option<string>,
}

let buildDefaultRegistryWith = (_deps: deps): providerRegistry => {
  // Future: pass deps to each provider creator. For now, providers use the
  // hardcoded CredentialResolver, so _deps is unused.
  buildDefaultRegistry()
}
