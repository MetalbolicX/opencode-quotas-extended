// src/Auth/AuthJsonSource.res
// Reads credentials from $XDG_DATA_HOME/opencode/auth.json (or default).
// Ported from src/adapters/auth/auth-json-source.ts.

let readJson = (path: string): option<JSON.t> => {
  try {
    let content = Node.readFileSync(path)
    Some(JSON.parseOrThrow(content))
  } catch {
  | _ => None
  }
}

let getCredential = (providerId: string): option<Credential.credential> => {
  let path = Paths.getAuthJsonPath(~env=None)
  switch readJson(path) {
  | None => None
  | Some(json) =>
    switch json {
    | JSON.Object(dict) =>
      let key = ProviderKeys.authKey(providerId)
      switch Dict.get(dict, key) {
      | None => None
      | Some(entry) => Credential.fromJson(entry)
      }
    | _ => None
    }
  }
}

@module("node:fs") external renameSync: (string, string) => unit = "renameSync"

let persistOAuthTokens = (
  ~env: option<dict<string>>,
  providerId: string,
  access: string,
  refresh: string,
  expiresMs: float,
): bool => {
  let path = Paths.getAuthJsonPath(~env)
  switch readJson(path) {
  | Some(JSON.Object(root)) =>
    let key = ProviderKeys.authKey(providerId)
    switch Dict.get(root, key) {
    | Some(JSON.Object(entry)) =>
      Dict.set(entry, "access", JSON.String(access))
      Dict.set(entry, "refresh", JSON.String(refresh))
      Dict.set(entry, "expires", JSON.Number(expiresMs))
      let tempPath = path ++ ".tmp"
      try {
        let _ = Node.writeFileSync(tempPath, JSON.stringify(JSON.Object(root)))
        renameSync(tempPath, path)
        true
      } catch {
      | _ => false
      }
    | _ => false
    }
  | _ => false
  }
}
