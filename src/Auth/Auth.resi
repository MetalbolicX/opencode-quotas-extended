// Auth barrel - re-exports all auth module types.

type credential = Credential.credential
let fromJson: JSON.t => option<credential>
