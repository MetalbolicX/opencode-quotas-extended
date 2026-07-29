// CredentialSource — domain reads credentials through this port (DIP).
// Credential = Option A: single record with variant field (string) + optional fields.

/** CredentialVariant matches authStrategy on Provider */
type credentialVariant = [ #api | #oauth | #wellknown | #env ]

type apiCredential = {
  variant: string,
  key: string,
}

type oAuthCredential = {
  access: string,
  refresh: string,
  expires: float, // Unix timestamp
}

type wellknownCredential = {
  key: string,
  token: string,
}

type envCredential = {
  envVar: string,
}

/** Single record with variant field — NOT a tagged union */
type credential =
  | Api(apiCredential)
  | OAuth(oAuthCredential)
  | Wellknown(wellknownCredential)
  | Env(envCredential)

/** Returns the credential for a provider, or null if none is available. */
type credentialSource = {
  get: string => promise<option<credential>>,
}
