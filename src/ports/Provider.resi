// QuotaProvider — each adapter implements this port.
// The domain depends ONLY on this interface (DIP).

open Domain

/** "api" | "oauth" | "wellknown" | "env" */
type authStrategy = [ #api | #oauth | #wellknown | #env ]

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  /**
   * Returns true when the provider is available (credentials present, network reachable, etc.).
   * Adapters resolve their own credentials via the injected CredentialSource.
   */
  isAvailable: unit => promise<bool>,
  /**
   * Fetches quota data for this provider. Returns an array (one entry per tracked resource).
   * Adapters resolve their own credentials via the injected CredentialSource.
   */
  fetchQuotas: unit => promise<array<quotaData>>,
}
