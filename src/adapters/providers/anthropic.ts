// Anthropic provider — api variant, env key ANTHROPIC_API_KEY.
// Endpoint: TODO(research) — see USAGE_URL.
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";

/** TODO(research): pin exact URL before production use.
 *  Candidate: https://api.anthropic.com/v1/organizations/{org_id}/usage
 *  Auth: x-api-key header, anthropic-version: 2023-06-01 */
const USAGE_URL = "TODO(research): https://api.anthropic.com/v1/organizations/{org_id}/usage";

function toNum(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const p = Number.parseFloat(v); if (Number.isFinite(p)) return p; }
  return null;
}

export function createAnthropicProvider(
  credSrc: CredentialSource,
  http: HttpClient,
): QuotaProvider {
  return {
    id: "anthropic",
    displayName: "Anthropic",
    category: "api-spend",
    authStrategy: "env",

    async isAvailable(): Promise<boolean> {
      const cred = await credSrc.get("anthropic");
      return cred !== null;
    },

    async fetchQuotas(): Promise<QuotaData[]> {
      if (USAGE_URL.startsWith("TODO")) {
        console.warn("[anthropic] Endpoint pending research.");
        return [];
      }
      const cred = await credSrc.get("anthropic");
      if (!cred || cred.variant !== "api") return [];
      const key = cred.key;
      try {
        const data = await http.request<{ usage?: unknown }>(
          {
            url: USAGE_URL,
            method: "GET",
            headers: {
              "x-api-key": key,
              "anthropic-version": "2023-06-01",
            },
          },
          { timeoutMs: 15_000, retries: 0, redact: true },
        );
        if (!data || typeof data !== "object") return [];
        // TODO: parse response shape once endpoint is confirmed via live capture
        void data;
        return [];
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.warn(`[anthropic] fetch failed: ${msg.replace(/[^\x20-\x7E]/g, "?").slice(0, 80)}`);
        return [];
      }
    },
  };
}
