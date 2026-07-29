// src/Infra/Paths.res
// Path resolution following XDG Base Directory spec.

type env = option<dict<string>>

let join3 = (a: string, b: string, c: string): string =>
  Node.pathJoin(Node.pathJoin(a, b), c)

let getDataHome = (~env: option<dict<string>>) => {
  let source = switch env {
  | Some(v) => v
  | None => %raw("process.env")
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
