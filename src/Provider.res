// Provider — port interface for quota providers.
// The domain layer depends ONLY on this interface (DIP).

open Domain

/** "api" | "oauth" | "wellknown" | "env" */
type authStrategy = [#api | #oauth | #wellknown | #env]

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  // S2: label of the first locally selected credential source
  // ("opencode" | "pi" | "claude-code" | "env" | "config" | "mmx"), or None when
  // no source selects a credential. This is a label, never credential material,
  // and it is derived without fetching quota data or refreshing tokens.
  credentialSource: unit => promise<option<string>>,
  fetchQuotas: unit => promise<array<quotaData>>,
}
