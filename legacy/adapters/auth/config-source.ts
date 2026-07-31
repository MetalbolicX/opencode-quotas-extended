// config-source: resolves credentials from quotas.json config override.
import type { Credential } from "../../ports/credentials.js";
import type { QuotasConfig } from "../infra/config-loader.js";

export function createConfigSource(config: QuotasConfig): (providerId: string) => Credential | null {
  return function get(providerId: string): Credential | null {
    const ov = config.credentials?.[providerId];
    if (!ov) return null;
    if (ov.type === "api") return { variant: "api", key: ov.key };
    if (ov.type === "env") return { variant: "env", envVar: ov.envVar };
    return null;
  };
}
