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
        let configPath = Node.pathJoin(Node.pathJoin(%raw("process.cwd()"), ".opencode"), "quotas.json")
        let config = ConfigLoader.loadConfig(~configPath, ())
        ConfigSource.getCredential(config, providerId)
      }
    }
  )
}
