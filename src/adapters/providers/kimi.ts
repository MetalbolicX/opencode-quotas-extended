// Kimi / Moonshot — no public quota API available.
// Moonshot/Kimi does not expose a public usage/quota endpoint.
// The OpenAI-compatible API only serves chat completions.
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";

export function createKimiProvider(_credSrc: CredentialSource, _http: HttpClient, _logger?: Logger): QuotaProvider {
  return {
    id: "kimi", displayName: "Kimi / Moonshot", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await _credSrc.get("kimi-for-coding")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      return [];
    },
  };
}
