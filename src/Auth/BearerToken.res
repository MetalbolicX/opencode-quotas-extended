// src/Auth/BearerToken.res
// Shared bearer-token extraction from Credential.credential variants.
// Lifted verbatim from src/Providers/Zai.res (the canonical 4-arm version).

open Credential

let extract = (cred: credential): string => {
  switch cred {
  | Api(c) => `Bearer ${c.key}`
  | OAuth(c) => `Bearer ${c.access}`
  | Wellknown(c) => `Bearer ${c.token}`
  | Env(c) =>
    switch Node.processEnv->Dict.get(c.envVar) {
    | Some(v) => v
    | None => ""
    }
  }
}
