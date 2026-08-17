// Priority resolver: auth.json → env → config.

let resolve: string => Promise.t<option<Credential.credential>>

let resolveOrEmpty: (
  ~key: string,
  ~fn: Credential.credential => Promise.t<array<Domain.quotaData>>,
) => Promise.t<array<Domain.quotaData>>
