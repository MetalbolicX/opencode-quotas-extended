// Kimi / Moonshot provider.
// Endpoint: no public quota API — follows the coding-plan pattern.
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseMonitorLimits } from "./coding-plan-parse.js";

// Placeholder — Kimi has no public quota API; callers inject fixture for testing.
var USAGE_URL = "https://api.moonshot.cn/api/usage/quota";

export function createKimiProvider(credSrc: CredentialSource, http: HttpClient, _logger?: Logger): QuotaProvider {
  return {
    id: "kimi", displayName: "Kimi / Moonshot", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("kimi-for-coding")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return withOAuth(credSrc, http, "kimi-for-coding", async (c) =>
        parseMonitorLimits(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "kimi", "Kimi")
      );
    },
  };
}
