// z.ai Coding Plan provider — oauth variant.
// Endpoint: https://api.z.ai/api/monitor/usage/quota/limit
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseZaiLimits } from "./coding-plan-parse.js";

var USAGE_URL = "https://api.z.ai/api/monitor/usage/quota/limit";

export function createZaiProvider(credSrc: CredentialSource, http: HttpClient, _logger?: Logger): QuotaProvider {
  return {
    id: "zai", displayName: "z.ai Coding Plan", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("zai-coding-plan")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return withOAuth(credSrc, http, "zai-coding-plan", async (c) =>
        parseZaiLimits(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "zai", "z.ai")
      );
    },
  };
}
