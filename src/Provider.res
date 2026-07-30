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
  fetchQuotas: unit => promise<array<quotaData>>,
}
