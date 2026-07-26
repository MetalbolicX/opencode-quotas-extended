// CredentialSource — domain reads credentials through this port (DIP).

export type CredentialVariant = "api" | "oauth" | "wellknown" | "env";

export interface ApiCredential {
  readonly variant: "api";
  readonly key: string;
}

export interface OAuthCredential {
  readonly variant: "oauth";
  readonly access: string;
  readonly refresh: string;
  readonly expires: number; // Unix timestamp
}

export interface WellknownCredential {
  readonly variant: "wellknown";
  readonly key: string;
  readonly token: string;
}

export interface EnvCredential {
  readonly variant: "env";
  readonly envVar: string;
}

export type Credential =
  | ApiCredential
  | OAuthCredential
  | WellknownCredential
  | EnvCredential;

/** Returns the credential for a provider, or null if none is available. */
export interface CredentialSource {
  get(providerId: string): Promise<Credential | null>;
}
