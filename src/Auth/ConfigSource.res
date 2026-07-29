// src/Auth/ConfigSource.res
// Resolves credentials from quotas.json config override.
// Ported from src/adapters/auth/config-source.ts.

let getCredential = (
  config: ConfigLoader.quotasConfig,
  providerId: string,
): option<Credential.credential> => {
  switch config.credentials {
  | None => None
  | Some(json) =>
    switch json {
    | JSON.Object(dict) =>
      switch Dict.get(dict, providerId) {
      | None => None
      | Some(entry) => Credential.fromJson(entry)
      }
    | _ => None
    }
  }
}
