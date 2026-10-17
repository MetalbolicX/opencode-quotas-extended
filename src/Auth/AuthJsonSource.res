// src/Auth/AuthJsonSource.res
// Reads credentials from harness auth.json files: opencode ($XDG_DATA_HOME/opencode/auth.json)
// and pi ($PI_CODING_AGENT_DIR/auth.json). Writes only ever target opencode's file.
// Ported from src/adapters/auth/auth-json-source.ts.

let readJson = (path: string): option<JSON.t> => {
  try {
    let content = Node.readFileSync(path)
    Some(JSON.parseOrThrow(content))
  } catch {
  | _ => None
  }
}

// Reads one entry from any harness auth.json (opencode and pi share the layout:
// a top-level object keyed by provider id).
let getCredentialAt = (~path: string, ~key: string): option<Credential.credential> => {
  switch readJson(path) {
  | Some(JSON.Object(dict)) =>
    switch Dict.get(dict, key) {
    | None => None
    | Some(entry) => Credential.fromJson(entry)
    }
  | _ => None
  }
}

let getOpencodeCredential = (~env: option<dict<string>>, providerId: string): option<Credential.credential> =>
  getCredentialAt(~path=Paths.getAuthJsonPath(~env), ~key=ProviderKeys.authKey(providerId))

// pi's auth.json is read-only for this tool: pi locks and rotates it itself.
let getPiCredential = (~env: option<dict<string>>, providerId: string): option<Credential.credential> =>
  switch ProviderKeys.piAuthKey(providerId) {
  | None => None
  | Some(key) => getCredentialAt(~path=Paths.getPiAuthJsonPath(~env), ~key)
  }

let getCredential = (providerId: string): option<Credential.credential> =>
  getOpencodeCredential(~env=None, providerId)

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
