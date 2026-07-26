// opencode Zen provider — api variant.
// Endpoint: https://opencode.ai/api/billing/balance (confirmed by live capture).
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseUsage } from "./coding-plan-parse.js";

var USAGE_URL = "https://opencode.ai/api/billing/balance";

export function createZenProvider(credSrc: CredentialSource, http: HttpClient): QuotaProvider {
  return {
    id: "zen", displayName: "opencode Zen", category: "subscription", authStrategy: "api",
    async isAvailable() { return (await credSrc.get("opencode")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return withOAuth(credSrc, http, "opencode", async (c) =>
        parseUsage(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "zen", "Zen")
      ).catch(() => [] as QuotaData[]);
    },
  };
}
