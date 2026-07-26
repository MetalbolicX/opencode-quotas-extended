// Kimi / Moonshot Coding Plan provider — oauth variant.
// Endpoint: https://platform.moonshot.ai/api/v1/usage (probe returned 301 redirect → 404; key may lack scope).
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseUsage } from "./coding-plan-parse.js";

var USAGE_URL = "https://platform.moonshot.ai/api/v1/usage";

export function createKimiProvider(credSrc: CredentialSource, http: HttpClient): QuotaProvider {
  return {
    id: "kimi", displayName: "Kimi / Moonshot", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("kimi-for-coding")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return withOAuth(credSrc, http, "kimi-for-coding", async (c) =>
        parseUsage(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "kimi", "Kimi")
      ).catch(() => [] as QuotaData[]);
    },
  };
}
