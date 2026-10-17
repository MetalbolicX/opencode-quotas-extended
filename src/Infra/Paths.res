// src/Infra/Paths.res
// Path resolution following XDG Base Directory spec.

type env = option<dict<string>>

let join3 = (a: string, b: string, c: string): string =>
  Node.pathJoin(Node.pathJoin(a, b), c)

let getDataHome = (~env: option<dict<string>>) => {
  let source = switch env {
  | Some(v) => v
  | None => Node.processEnv
  }
  switch Dict.get(source, "XDG_DATA_HOME") {
  | Some(v) if v !== "" => Some(v)
  | _ => None
  }
}

let getAuthJsonPath = (~env: option<dict<string>>) => switch getDataHome(~env) {
| Some(home) => join3(home, "opencode", "auth.json")
| None => join3(Node.osHomedir(), ".local/share/opencode", "auth.json")
}

let getHistoryPath = (~env: option<dict<string>>) => switch getDataHome(~env) {
| Some(home) => join3(home, "opencode", "quota-history.json")
| None => join3(Node.osHomedir(), ".local/share/opencode", "quota-history.json")
}

let envSource = (~env: option<dict<string>>): dict<string> => switch env {
| Some(v) => v
| None => Node.processEnv
}

// Mirrors pi's own expandTildePath for PI_CODING_AGENT_DIR values like "~/pi".
let expandTilde = (path: string): string =>
  if path === "~" {
    Node.osHomedir()
  } else if String.startsWith(path, "~/") {
    Node.pathJoin(Node.osHomedir(), String.slice(path, ~start=2))
  } else {
    path
  }

// pi's agent dir: $PI_CODING_AGENT_DIR, else ~/.pi/agent (pi config.js getAgentDir).
let getPiAuthJsonPath = (~env: option<dict<string>>) =>
  switch Dict.get(envSource(~env), "PI_CODING_AGENT_DIR") {
  | Some(dir) if dir !== "" => Node.pathJoin(expandTilde(dir), "auth.json")
  | _ => join3(Node.osHomedir(), ".pi/agent", "auth.json")
  }
