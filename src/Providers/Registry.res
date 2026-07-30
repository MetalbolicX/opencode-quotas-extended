// src/Providers/Registry.res
// Provider registry — wires all 8 provider creators into a single registry.
// Mirrors src/adapters/providers/registry.ts (TS version retained for rollback safety).

// --- Shared structural provider type -------------------------------------------
// All 8 providers define their own local quotaProvider type that is structurally
// identical. We use a shared record type here so the registry array is homogeneous.
// Obj.magic coerces each provider's nominal type to the structural shared type.

type sharedProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: [#api | #oauth | #wellknown | #env],
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<Domain.quotaData>>,
}

// --- Registry type ------------------------------------------------------------

type providerRegistry = {
  ids: unit => array<string>,
  get: string => option<sharedProvider>,
  all: unit => array<sharedProvider>,
}

// --- Type-safe coercion (runtime no-op, ReScript erased at compile time) --------
// Each provider module defines its own local quotaProvider type (nominal).
// These are all structurally identical, but ReScript won't mix nominal types in
// arrays. Obj.magic erases the type boundary so the array is homogeneous.

let private_coerce: 'a => sharedProvider = %raw("(v) => v")

// --- All provider creators -----------------------------------------------------

let allProviders = (): array<sharedProvider> => [
  private_coerce(OpenAI.createOpenAIProvider()),
  private_coerce(Zen.createZenProvider()),
  private_coerce(Go.createGoProvider()),
  private_coerce(Zai.createZaiProvider()),
  private_coerce(Kimi.createKimiProvider()),
  private_coerce(Minimax.createMinimaxProvider()),
  private_coerce(Anthropic.createAnthropicProvider()),
  private_coerce(Gemini.createGeminiProvider()),
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
