// src/Auth/Credential.res
// Shared credential type — redeclared locally so Auth module adapters
// don't depend directly on ports/credentials.ts (which stays untouched).
// Mirrors the Credential variant from src/ports/credentials.ts.

type credential =
  | Api({variant: string, key: string})
  | OAuth({variant: string, access: string, refresh: string, expires: float})
  | Wellknown({variant: string, key: string, token: string})
  | Env({variant: string, envVar: string})

// Decode a credential from JSON. Handles both the credentialEntry schema
// (config source: {type:"api",key:} | {type:"env",envVar:}) and the auth.json
// schema (auth-json source: {type:"api",key:} | {type:"oauth",...} | {type:"wellknown",...}).
let fromJson = (json: JSON.t): option<credential> => {
  switch json {
  | JSON.Object(dict) =>
    switch Dict.get(dict, "type") {
    | Some(JSON.String("api")) =>
      switch Dict.get(dict, "key") {
      | Some(JSON.String(k)) => Some(Api({variant: "api", key: k}))
      | _ => None
      }
    | Some(JSON.String("env")) =>
      switch Dict.get(dict, "envVar") {
      | Some(JSON.String(e)) => Some(Env({variant: "env", envVar: e}))
      | _ => None
      }
    | Some(JSON.String("oauth")) =>
      switch (Dict.get(dict, "access"), Dict.get(dict, "refresh"), Dict.get(dict, "expires")) {
      | (Some(JSON.String(a)), Some(JSON.String(r)), expires) =>
        let expiresVal = switch expires {
        | Some(JSON.Number(n)) => n
        | _ => 0.0
        }
        Some(OAuth({variant: "oauth", access: a, refresh: r, expires: expiresVal}))
      | _ => None
      }
    | Some(JSON.String("wellknown")) =>
      switch (Dict.get(dict, "key"), Dict.get(dict, "token")) {
      | (Some(JSON.String(k)), Some(JSON.String(t))) => Some(Wellknown({variant: "wellknown", key: k, token: t}))
      | _ => None
      }
    | _ => None
    }
  | _ => None
  }
}
