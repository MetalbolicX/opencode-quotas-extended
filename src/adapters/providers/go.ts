// opencode Go provider — api variant.
// Endpoint: same family as Zen — https://opencode.ai/api/billing/balance (probed with opencode-go credential).
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseUsage } from "./coding-plan-parse.js";

var USAGE_URL = "https://opencode.ai/api/billing/balance";

export function createGoProvider(credSrc: CredentialSource, http: HttpClient): QuotaProvider {
  return {
    id: "go", displayName: "opencode Go", category: "subscription", authStrategy: "api",
    async isAvailable() { return (await credSrc.get("opencode-go")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return withOAuth(credSrc, http, "opencode-go", async (c) =>
        parseUsage(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "go", "Go")
      ).catch(() => [] as QuotaData[]);
    },
  };
}
