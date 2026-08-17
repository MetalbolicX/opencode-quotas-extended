// src/Auth/CredentialResolver.res
// Priority resolver: auth.json → env → config.
// Wraps the sync body in Promise.resolve (no async work; matches TS contract).
// Ported from src/adapters/auth/credential-resolver.ts.

let resolve = (providerId: string): Promise.t<option<Credential.credential>> => {
  Promise.resolve(
    switch AuthJsonSource.getCredential(providerId) {
    | Some(c) => Some(c)
    | None =>
      switch EnvSource.getCredential(providerId, Node.processEnv) {
      | Some(c) => Some(c)
      | None =>
        let configPath = Node.pathJoin(Node.pathJoin(Node.processCwd(), ".opencode"), "quotas.json")
        let config = ConfigLoader.loadConfig(~configPath, ())
        ConfigSource.getCredential(config, providerId)
      }
    }
  )
}

// resolveOrEmpty: resolves credential for key, returns [] on None, calls fn(c) on Some.
let resolveOrEmpty = (~key: string, ~fn: Credential.credential => Promise.t<array<Domain.quotaData>>): Promise.t<array<Domain.quotaData>> => {
  resolve(key)->Promise.then(opt =>
    switch opt {
    | None => Promise.resolve([])
    | Some(c) => fn(c)
    }
  )
}
