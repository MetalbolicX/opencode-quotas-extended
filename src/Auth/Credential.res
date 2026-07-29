// src/Auth/Credential.res
// Shared credential type — redeclared locally so Auth module adapters
// don't depend directly on ports/credentials.ts (which stays untouched).
// Mirrors the Credential variant from src/ports/credentials.ts.

type credential =
  | Api({variant: string, key: string})
  | OAuth({variant: string, access: string, refresh: string, expires: float})
  | Wellknown({variant: string, key: string, token: string})
  | Env({variant: string, envVar: string})
