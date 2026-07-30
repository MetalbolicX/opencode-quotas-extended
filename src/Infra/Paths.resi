// src/Infra/Paths.resi
// Path resolution following XDG Base Directory spec.

type env = option<dict<string>>

let getDataHome: (~env: env) => option<string>
let getAuthJsonPath: (~env: env) => string
let getHistoryPath: (~env: env) => string
