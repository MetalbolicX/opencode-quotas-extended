// Provider.resi — port interface for quota providers.
// The domain layer depends ONLY on this interface (DIP).

type authStrategy = [#api | #oauth | #wellknown | #env]
type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  // First locally selected credential-source label (opencode | pi | claude-code |
  // env | config | mmx), or None when nothing is configured.
  credentialSource: unit => promise<option<string>>,
  fetchQuotas: unit => promise<array<Domain.quotaData>>,
}
