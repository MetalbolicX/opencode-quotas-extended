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
