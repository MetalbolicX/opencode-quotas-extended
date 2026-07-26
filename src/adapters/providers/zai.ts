// z.ai Coding Plan provider — oauth variant.
// Endpoint: https://api.z.ai/api/coding-plan/usage (live capture: returned 200 + {"code":500,"msg":"404 NOT_FOUND"} in body — key may lack this scope).
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseUsage } from "./coding-plan-parse.js";

var USAGE_URL = "https://api.z.ai/api/coding-plan/usage";

export function createZaiProvider(credSrc: CredentialSource, http: HttpClient): QuotaProvider {
  return {
    id: "zai", displayName: "z.ai Coding Plan", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("zai-coding-plan")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return withOAuth(credSrc, http, "zai-coding-plan", async (c) =>
        parseUsage(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "zai", "z.ai")
      ).catch(() => [] as QuotaData[]);
    },
  };
}
