// Priority resolver: harness auth.json files (opencode → pi, reorderable via
// quotas.json credentialSources) → env → config, with candidate fallthrough.

type origin = [#opencode | #pi | #claudeCode | #env | #config]

type candidate = {credential: Credential.credential, origin: origin}

let resolveAllWith: (~env: dict<string>, ~configPath: string, string) => array<candidate>

let resolveAll: string => Promise.t<array<candidate>>

let resolve: string => Promise.t<option<Credential.credential>>

let expiredHint: string

let isFallthroughError: exn => bool

let tryCandidates: (
  array<candidate>,
  candidate => Promise.t<array<Domain.quotaData>>,
) => Promise.t<array<Domain.quotaData>>

let resolveEach: (
  ~key: string,
  ~fn: candidate => Promise.t<array<Domain.quotaData>>,
) => Promise.t<array<Domain.quotaData>>

let resolveOrEmpty: (
  ~key: string,
  ~fn: Credential.credential => Promise.t<array<Domain.quotaData>>,
) => Promise.t<array<Domain.quotaData>>
