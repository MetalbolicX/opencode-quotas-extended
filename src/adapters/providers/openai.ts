// OpenAI provider — supports oauth (ChatGPT Plus/Pro) and api (platform key) variants.
import type { Credential, CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { withOAuth } from "./oauth.js";

const WHAM_URL = "https://chatgpt.com/backend-api/wham/usage";
/** Confirmed: https://api.openai.com/v1/usage — requires API key (not OAuth token). */
const PLATFORM_URL = "https://api.openai.com/v1/usage";
/** Pagination cap: prevents runaway loops on a misbehaving OpenAI API response. */
const MAX_PAGES = 20;

function isObj(v: unknown): v is Record<string, unknown> {
  return Boolean(v) && typeof v === "object" && !Array.isArray(v);
}

function toNum(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const p = Number.parseFloat(v); if (Number.isFinite(p)) return p; }
  return null;
}

function resetDate(after: number | null, at: number | null): Date | null {
  if (at !== null) return new Date(at * 1000);
  if (after !== null) return new Date(Date.now() + after * 1000);
  return null;
}

export function createOpenAIProvider(
  credentialSource: CredentialSource,
  http: HttpClient,
): QuotaProvider {
  return {
    id: "openai",
    displayName: "OpenAI",
    category: "subscription",
    authStrategy: "oauth",

    async isAvailable(): Promise<boolean> {
      const cred = await credentialSource.get("openai");
      if (!cred) return false;
      return true; // oauth/api/wellknown/env — all imply credential is present
    },

    async fetchQuotas(): Promise<QuotaData[]> {
      const cred = await credentialSource.get("openai");
      if (!cred) return [];

      if (cred.variant === "oauth") {
        try {
          return await withOAuth(credentialSource, http, "openai", async (client) => {
            const rl = (await client.request<{ rate_limit?: { primary_window?: Record<string, unknown>; secondary_window?: Record<string, unknown> }; credits?: { unlimited?: boolean; balance?: string | null } }>(
              { url: WHAM_URL, method: "GET" },
              { timeoutMs: 15_000, retries: 0, redact: true },
            )) as { rate_limit?: { primary_window?: Record<string, unknown>; secondary_window?: Record<string, unknown> }; credits?: { unlimited?: boolean; balance?: string | null } };

            const entries: QuotaData[] = [];
            for (const [id, label, win] of [["openai-primary", "OpenAI Primary", "daily"], ["openai-secondary", "OpenAI Secondary", "rolling"]] as [string, string, string][]) {
              const w = rl?.rate_limit?.[id === "openai-primary" ? "primary_window" : "secondary_window"];
              if (!w) continue;
              const used = toNum(w.used_percent);
              if (used === null) continue;
              entries.push({ id, providerName: label, used: Math.max(0, Math.min(100, used)), limit: 100, unit: "%", window: win as "daily" | "rolling", reset: resetDate(toNum(w.reset_after_seconds), toNum(w.reset_at)), predictedReset: null, info: label });
            }
            const credits = rl?.credits;
            if (credits) {
              if (credits.unlimited) entries.push({ id: "openai-credits", providerName: "OpenAI Credits", used: 0, limit: null, unit: "credits", window: "rolling", reset: null, predictedReset: null, info: "unlimited" });
              else { const bal = toNum(credits.balance ?? null); if (bal !== null) entries.push({ id: "openai-credits", providerName: "OpenAI Credits", used: bal, limit: null, unit: "credits", window: "rolling", reset: null, predictedReset: null, info: "balance" }); }
            }
            return entries;
          }) as QuotaData[];
        } catch { return []; }
      }

      // api / wellknown / env — cursor-based pagination via has_more + next_page.
      // Aggregate all pages with first-write-wins dedup by entry id.
      // Failure isolation: if page 1 succeeds but page N throws, return accumulated entries.
      const key = cred.variant === "api" || cred.variant === "wellknown" ? cred.key : process.env[cred.envVar] ?? "";
      const seenIds = new Set<string>();
      const allEntries: QuotaData[] = [];
      let pageCursor: string | null = null;
      for (let p = 0; p < MAX_PAGES; p++) {
        const builtUrl: string = pageCursor ? `${PLATFORM_URL}?page=${encodeURIComponent(pageCursor)}` : PLATFORM_URL;
        try {
          // eslint-disable-next-line no-await-in-loop
          const resp: {
            data?: unknown[];
            total_usage?: unknown;
            limit_user?: unknown;
            has_more?: unknown;
            next_page?: unknown;
          } = await http.request(
            { url: builtUrl, method: "GET", headers: { Authorization: `Bearer ${key}` } },
            { timeoutMs: 15_000, retries: 0, redact: true },
          );
          // Defensive parse of data array — each entry may have id, model, generated.
          const dataArr = Array.isArray(resp?.data) ? resp.data : [];
          for (const entry of dataArr) {
            if (!isObj(entry)) continue;
            const e = entry as Record<string, unknown>;
            // first-write-wins deduplication
            const id = typeof e.id === "string" ? e.id : null;
            if (id && seenIds.has(id)) continue;
            if (id) seenIds.add(id);
            const used = toNum(e.generated);
            if (used === null) continue;
            const model = typeof e.model === "string" ? e.model : "openai-api";
            allEntries.push({
              id: `openai-api-${id ?? model}`,
              providerName: `OpenAI ${model}`,
              used,
              limit: toNum(resp.limit_user) ?? null,
              unit: "tokens",
              window: "rolling",
              reset: null,
              predictedReset: null,
              info: model,
            });
          }
          // Defensive: treat malformed has_more/next_page as terminal.
          if (!resp?.has_more || !resp?.next_page) break;
          // next_page must be a non-empty string to continue.
          if (typeof resp.next_page !== "string" || !resp.next_page) break;
          pageCursor = resp.next_page;
        } catch {
          // Failure isolation: if we already accumulated entries, return them silently.
          // First-page failure still throws (returns []), matching existing behavior.
          if (allEntries.length > 0) return allEntries;
          return [];
        }
      }
      return allEntries;
    },
  };
}
