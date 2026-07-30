// Shared credential type — mirrors the Credential variant from src/ports/credentials.ts.

type credential =
  | Api({variant: string, key: string})
  | OAuth({variant: string, access: string, refresh: string, expires: float})
  | Wellknown({variant: string, key: string, token: string})
  | Env({variant: string, envVar: string})

let fromJson: JSON.t => option<credential>
