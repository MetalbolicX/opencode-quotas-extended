// credential-resolver: composes auth.json → env → config override, returns first non-null.
import { readFileSync } from "node:fs";
import type { Credential } from "../../ports/credentials.js";
import { createAuthJsonSource } from "./auth-json-source.js";
import { createEnvSource } from "./env-source.js";
import { createConfigSource } from "./config-source.js";
import { DEFAULTS } from "../infra/config-loader.js";
import type { QuotasConfig } from "../infra/config-loader.js";

export function createCredentialResolver(
  config: QuotasConfig,
  fs: { readFileSync: (path: string) => string },
  env: Record<string, string | undefined>,
): { get(providerId: string): Promise<Credential | null> } {
  const authJson = createAuthJsonSource(fs, env as Record<string, string | undefined>);
  const envSrc = createEnvSource(env as Record<string, string | undefined>);
  const cfgSrc = createConfigSource(config);
  return { async get(id) { return authJson(id) ?? envSrc(id) ?? cfgSrc(id); } };
}

let _resolver: { get: (id: string) => Promise<Credential | null> } | null = null;

export function getCredentialResolver() {
  if (!_resolver) _resolver = createCredentialResolver(DEFAULTS as QuotasConfig, { readFileSync: (p) => readFileSync(p, "utf-8") }, process.env as Record<string, string | undefined>);
  return _resolver;
}

export const credentialResolver = { get: (id: string) => getCredentialResolver().get(id) };
