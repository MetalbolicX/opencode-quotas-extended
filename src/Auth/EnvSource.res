// src/Auth/EnvSource.res
// Resolves credentials from environment variables.
// Ported from src/adapters/auth/env-source.ts.

let envVarFor = (providerId: string): option<string> => {
  switch providerId {
  | "openai" => Some("OPENAI_API_KEY")
  | "anthropic" => Some("ANTHROPIC_API_KEY")
  | "google-gemini" => Some("GEMINI_API_KEY")
  | _ => None
  }
}

let getCredential = (providerId: string, env: Dict.t<string>): option<Credential.credential> => {
  switch envVarFor(providerId) {
  | None => None
  | Some(varName) =>
    switch Dict.get(env, varName) {
    | None => None
    | Some(value) if value === "" => None
    | Some(value) => Some(Credential.Api({variant: "api", key: value}))
    }
  }
}
