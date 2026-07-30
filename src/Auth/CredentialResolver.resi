// Priority resolver: auth.json → env → config.

let resolve: string => Promise.t<option<Credential.credential>>
