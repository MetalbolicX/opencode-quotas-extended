// src/Auth/Redactor.res
// Recursive redaction of sensitive keys in credential-shaped JSON.
// Ported from src/adapters/auth/redactor.ts.

let isSensitiveKey = (k: string): bool => {
  let lower = k->String.toLowerCase
  lower == "access" || lower == "refresh" || lower == "token" ||
  lower == "key" || lower == "apikey" || lower == "password" || lower == "secret"
}

let maskString = (s: string): string => {
  let isSk = s->String.startsWith("sk-")
  let prefix = if isSk { 4 } else { 3 }
  let end = prefix < s->String.length ? prefix : s->String.length
  let p = s->String.slice(~start=0, ~end)
  `${p}****`
}

let rec redactJson = (json: JSON.t): JSON.t => {
  switch json {
  | JSON.Object(obj) =>
    let result = Dict.make()
    let keys = Dict.keysToArray(obj)
    keys->Belt.Array.forEach(k => {
      let v = switch Dict.get(obj, k) {
      | Some(val) => val
      | None => JSON.Null
      }
      let masked = if isSensitiveKey(k) {
        switch v {
        | JSON.String(s) => JSON.String(maskString(s))
        | _ => v  // preserve non-string values as-is (no coercion)
        }
      } else {
        switch v {
        | JSON.Object(_) => redactJson(v)
        | JSON.Array(arr) => JSON.Array(Belt.Array.map(arr, redactJson))
        | _ => v
        }
      }
      Dict.set(result, k, masked)
    })
    JSON.Object(result)
  | JSON.Array(arr) =>
    JSON.Array(Belt.Array.map(arr, redactJson))
  | other => other
  }
}

let redact = (cred: option<JSON.t>): option<JSON.t> => {
  cred->Belt.Option.map(redactJson)
}
