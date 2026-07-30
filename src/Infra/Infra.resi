// Infra barrel - re-exports public surface of all Infra modules.

let getDataHome: (~env: Paths.env) => option<string>
let getAuthJsonPath: (~env: Paths.env) => string
let getHistoryPath: (~env: Paths.env) => string

let request: (~logger: FetchHttp.logger=?, FetchHttp.httpRequest, FetchHttp.requestOptions) => promise<JSON.t>
let make: FetchHttp.logger => FetchHttp.httpClient

let loadConfig: (~configPath: string, ~_logger: ConfigLoader.logger=?, unit) => ConfigLoader.quotasConfig
let resolveAnthropicOrgId: (ConfigLoader.quotasConfig, ~auth: option<dict<dict<string>>>, ~env: option<dict<string>>, unit) => string
