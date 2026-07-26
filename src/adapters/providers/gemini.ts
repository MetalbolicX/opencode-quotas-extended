// Google Gemini provider — api variant, env key GEMINI_API_KEY (GOOGLE_API_KEY fallback).
// Endpoint: TODO(research) — see USAGE_URL.
// Uses a 1-token probe call to read rate-limit headers (X-RateLimit-Limit, X-RateLimit-Remaining, etc.).
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";

/** TODO(research): pin exact quota endpoint before production use.
 *  Candidate: https://generativelanguage.googleapis.com/v1beta/models?key=... or
 *  a dedicated quota endpoint under the same host. */
const USAGE_URL = "TODO(research): https://generativelanguage.googleapis.com/v1beta/...";


export function createGeminiProvider(
  credSrc: CredentialSource,
  http: HttpClient,
): QuotaProvider {
  return {
    id: "gemini",
    displayName: "Google Gemini",
    category: "api-spend",
    authStrategy: "env",

    async isAvailable(): Promise<boolean> {
      const cred = await credSrc.get("gemini");
      if (cred && cred.variant === "api") return true;
      return process.env.GOOGLE_API_KEY !== undefined;
    },

    async fetchQuotas(): Promise<QuotaData[]> {
      if (USAGE_URL.startsWith("TODO")) {
        console.warn("[gemini] Endpoint pending research.");
        return [];
      }
      const primary = await credSrc.get("gemini");
      const key = (primary && primary.variant === "api" ? primary.key : null)
        ?? process.env.GOOGLE_API_KEY
        ?? null;
      if (!key) return [];
      try {
        // Probe call: simple models list to read rate-limit headers
        const data = await http.request<unknown>(
          {
            url: USAGE_URL,
            method: "GET",
            headers: { "x-goog-api-key": key },
          },
          { timeoutMs: 15_000, retries: 0, redact: true },
        );
        void data;
        // TODO: parse response/rate-limit headers once endpoint confirmed via live capture
        return [];
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.warn(`[gemini] fetch failed: ${msg.replace(/[^\x20-\x7E]/g, "?").slice(0, 80)}`);
        return [];
      }
    },
  };
}
