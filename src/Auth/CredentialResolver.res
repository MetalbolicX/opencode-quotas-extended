// src/Auth/CredentialResolver.res
// Priority resolver: harness auth.json files (opencode → pi by default, reorderable
// via quotas.json `credentialSources`) → env → config.
// Every source that has a credential becomes a candidate, so a provider present in
// only one harness still resolves, and a provider in both can fall through to the
// next harness when the first credential is rejected or expired.
// Ported from src/adapters/auth/credential-resolver.ts.

type origin = [#opencode | #pi | #claudeCode | #env | #config]

type candidate = {credential: Credential.credential, origin: origin}

let defaultHarnesses: array<origin> = [#opencode, #pi]

let harnessOf = (name: string): option<origin> =>
  switch name {
  | "opencode" => Some(#opencode)
  | "pi" => Some(#pi)
  | _ => None
  }

let harnessCredential = (~env: dict<string>, harness: origin, providerId: string) =>
  switch harness {
  | #opencode => AuthJsonSource.getOpencodeCredential(~env=Some(env), providerId)
  | #pi => AuthJsonSource.getPiCredential(~env=Some(env), providerId)
  | #claudeCode | #env | #config => None
  }

let resolveAllWith = (~env: dict<string>, ~configPath: string, providerId: string): array<candidate> => {
  // An invalid quotas.json is reported by the CLI's own config load; here it only
  // means "no overrides", so resolution keeps working with the default order.
  let config = try ConfigLoader.loadConfig(~configPath, ()) catch {
  | _ => ConfigLoader.defaults
  }
  let harnesses = switch config.credentialSources {
  | Some(names) => names->Array.filterMap(harnessOf)
  | None => defaultHarnesses
  }
  let fromHarnesses = harnesses->Array.filterMap(harness =>
    harnessCredential(~env, harness, providerId)->Option.map(credential => {credential, origin: harness})
  )
  let fromEnv =
    EnvSource.getCredential(providerId, env)->Option.map(credential => {credential, origin: #env})
  let fromConfig =
    ConfigSource.getCredential(config, providerId)->Option.map(credential => {credential, origin: #config})
  Array.concat(fromHarnesses, [fromEnv, fromConfig]->Array.filterMap(c => c))
}

let defaultConfigPath = () => Node.pathJoin(Node.pathJoin(Node.processCwd(), ".opencode"), "quotas.json")

let resolveAll = (providerId: string): Promise.t<array<candidate>> =>
  Promise.resolve(resolveAllWith(~env=Node.processEnv, ~configPath=defaultConfigPath(), providerId))

let resolve = (providerId: string): Promise.t<option<Credential.credential>> =>
  resolveAll(providerId)->Promise.then(cands =>
    Promise.resolve(cands->Array.get(0)->Option.map(c => c.credential))
  )

// --- Fallthrough --------------------------------------------------------------

// Shared phrase for "this credential is expired and we may not refresh it".
// Providers embed it in their error message so the resolver can fall through.
let expiredHint = "expired — run"

let errorMessage = (err: exn): string =>
  switch JsExn.anyToExnInternal(err) {
  | JsExn(v) => Belt.Option.getWithDefault(JsExn.message(v), String.make(v))
  | e => String.make(e)
  }

// Only credential problems justify trying another source; network or server
// errors would fail the same way for every candidate.
let isFallthroughError = (err: exn): bool => {
  let message = errorMessage(err)
  String.includes(message, "HTTP 401") ||
  String.includes(message, "HTTP 403") ||
  String.includes(message, expiredHint)
}

let tryCandidates = (
  cands: array<candidate>,
  fn: candidate => Promise.t<array<Domain.quotaData>>,
): Promise.t<array<Domain.quotaData>> => {
  let rec attempt = (index: int) =>
    switch cands->Array.get(index) {
    | None => Promise.resolve([])
    | Some(c) =>
      fn(c)->Promise.catch(err =>
        if index + 1 < Array.length(cands) && isFallthroughError(err) {
          attempt(index + 1)
        } else {
          Promise.reject(err)
        }
      )
    }
  attempt(0)
}

// resolveEach: tries every candidate for key in priority order; [] when there is none.
let resolveEach = (
  ~key: string,
  ~fn: candidate => Promise.t<array<Domain.quotaData>>,
): Promise.t<array<Domain.quotaData>> =>
  resolveAll(key)->Promise.then(cands => tryCandidates(cands, fn))

// resolveOrEmpty: like resolveEach for providers that do not care about the origin.
let resolveOrEmpty = (
  ~key: string,
  ~fn: Credential.credential => Promise.t<array<Domain.quotaData>>,
): Promise.t<array<Domain.quotaData>> =>
  resolveEach(~key, ~fn=c => fn(c.credential))
