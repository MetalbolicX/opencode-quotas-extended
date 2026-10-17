// src/Auth/ClaudeCodeSource.res
// Read-only source for the Claude Code subscription credential.
// Reads $CLAUDE_CONFIG_DIR/.credentials.json (else ~/.claude/.credentials.json)
// and decodes `claudeAiOauth` into Credential.OAuth. Never writes: the Claude
// Code CLI owns that file and the user refreshes it with `claude`.
// Ported from the Anthropic OAuth shape recorded in the feature doc (L3).

let readJson = (path: string): option<JSON.t> => {
  try {
    let content = Node.readFileSync(path)
    Some(JSON.parseOrThrow(content))
  } catch {
  | _ => None
  }
}

let stringField = (dict: dict<JSON.t>, key: string): option<string> =>
  switch Dict.get(dict, key) {
  | Some(JSON.String(s)) if s !== "" => Some(s)
  | _ => None
  }

let numberField = (dict: dict<JSON.t>, key: string): option<float> =>
  switch Dict.get(dict, key) {
  | Some(JSON.Number(n)) => Some(n)
  | _ => None
  }

// `claudeAiOauth` is not the auth.json entry schema (it has no `type` field),
// so decode it explicitly. accessToken is required; refresh/expiry are optional.
let decodeClaudeOAuth = (entry: JSON.t): option<Credential.credential> =>
  switch entry {
  | JSON.Object(oauth) =>
    switch stringField(oauth, "accessToken") {
    | None => None
    | Some(access) =>
      Some(
        Credential.OAuth({
          variant: "oauth",
          access,
          refresh: Belt.Option.getWithDefault(stringField(oauth, "refreshToken"), ""),
          expires: Belt.Option.getWithDefault(numberField(oauth, "expiresAt"), 0.0),
        }),
      )
    }
  | _ => None
  }

let getCredential = (~env: option<dict<string>>): option<Credential.credential> =>
  switch readJson(Paths.getClaudeCredentialsPath(~env)) {
  | Some(JSON.Object(root)) =>
    switch Dict.get(root, "claudeAiOauth") {
    | Some(entry) => decodeClaudeOAuth(entry)
    | None => None
    }
  | _ => None
  }
