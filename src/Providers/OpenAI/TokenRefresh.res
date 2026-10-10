// Pure OpenAI OAuth refresh request and response helpers.
let tokenUrl = "https://auth.openai.com/oauth/token"
let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"

let needsRefresh = (expiresMs: float, nowMs: float): bool =>
  expiresMs > 0.0 && nowMs >= expiresMs -. 60000.0

let refreshRequestBody = (refreshToken: string): string => {
  let params = [
    "grant_type=refresh_token",
    `refresh_token=${encodeURIComponent(refreshToken)}`,
    `client_id=${encodeURIComponent(clientId)}`,
  ]
  params->Array.join("&")
}

type refreshResponse = {
  access: string,
  refresh: option<string>,
  expiresInSeconds: float,
}

let parseRefreshResponse = (json: string): option<refreshResponse> => {
  try {
    switch JSON.parseOrThrow(json) {
    | JSON.Object(dict) =>
      switch Dict.get(dict, "access_token") {
      | Some(JSON.String(access)) =>
        let refresh = switch Dict.get(dict, "refresh_token") {
        | Some(JSON.String(token)) => Some(token)
        | _ => None
        }
        let expiresInSeconds = switch Dict.get(dict, "expires_in") {
        | Some(JSON.Number(seconds)) => seconds
        | _ => 3600.0
        }
        Some({access, refresh, expiresInSeconds})
      | _ => None
      }
    | _ => None
    }
  } catch {
  | _ => None
  }
}
