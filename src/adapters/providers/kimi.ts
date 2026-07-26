// Kimi / Moonshot Coding Plan provider — oauth variant. Endpoint: TODO(research) — see USAGE_URL.
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";
import { parseUsage } from "./coding-plan-parse.js";

/** TODO(research): pin exact endpoint before production use. Candidate: https://platform.moonshot.ai/api/.../usage */
var USAGE_URL = "TODO(research): https://platform.moonshot.ai/api/.../usage";

export function createKimiProvider(credSrc: CredentialSource, http: HttpClient): QuotaProvider {
  return {
    id: "kimi", displayName: "Kimi / Moonshot", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("kimi-for-coding")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      if (USAGE_URL.startsWith("TODO")) { console.warn("[kimi] Endpoint pending research."); return []; }
      return withOAuth(credSrc, http, "kimi-for-coding", async (c) =>
        parseUsage(await c.request<unknown>({ url: USAGE_URL, method: "GET" }, { timeoutMs: 15_000, retries: 0, redact: true }), "kimi", "Kimi")
      ) as Promise<QuotaData[]>;
    },
  };
}
