// Anthropic provider — api variant, env key ANTHROPIC_API_KEY.
// Admin usage endpoint: https://api.anthropic.com/v1/organizations/{org_id}/usage
// Auth: x-api-key + anthropic-version: 2023-06-01
// orgId resolution: config → auth.json → ANTHROPIC_ORG_ID env.
// Paginated via has_more/next_page cursor, capped at 20 pages.
// Admin scope required: 401/403 surfaces as a clear actionable error (never silent []).
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import type { QuotasConfig } from "../infra/config-loader.js";
import { resolveAnthropicOrgId } from "../infra/config-loader.js";

const USAGE_URL = "https://api.anthropic.com/v1/organizations/{org_id}/usage";
const MAX_PAGES = 20;

const toNum = (v: unknown): number | null => {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const p = Number.parseFloat(v); if (Number.isFinite(p)) return p; }
  return null;
};

const isObj = (v: unknown): v is Record<string, unknown> => {
  return Boolean(v) && typeof v === "object" && !Array.isArray(v);
};

/** Maps an Anthropic admin-usage row to a QuotaData entry.
 * Token totals (input + output) are summed as the used value.
 * Window is inferred from time_bucket granularity (daily for YYYY-MM-DD prefixes).
 * Unknown fields are tolerated — defensive parse never throws. */
const mapRow = (row: Record<string, unknown>, idx: number): QuotaData | null => {
  const usage = isObj(row.usage) ? row.usage as Record<string, unknown> : {};
  const inputTokens = toNum(usage.input_tokens ?? usage.prompt_tokens);
  const outputTokens = toNum(usage.output_tokens ?? usage.completion_tokens);
  if (inputTokens === null && outputTokens === null) return null;
  const used = (inputTokens ?? 0) + (outputTokens ?? 0);
  const model = typeof row.model === "string" ? row.model : `row-${idx}`;
  const timeBucket = typeof row.time_bucket === "string" ? row.time_bucket : "";
  // Daily when time_bucket starts with a date; otherwise rolling.
  const window: "daily" | "monthly" | "rolling" =
    /^\d{4}-\d{2}-\d{2}/.test(timeBucket) ? "daily" : "rolling";
  return {
    id: `anthropic-${model}-${idx}`,
    providerName: `Anthropic ${model}`,
    used,
    limit: null,
    unit: "tokens",
    window,
    reset: null,
    info: `Anthropic ${model} (${timeBucket})`,
  }
}

/** Extended factory — accepts optional runtime context so orgId can be resolved
 * from config → auth.json → env (the three sources the pipeline owns).
 * The returned provider object satisfies the QuotaProvider port interface. */
export function createAnthropicProvider(
  credSrc: CredentialSource,
  http: HttpClient,
  config?: QuotasConfig,
  auth?: Record<string, unknown>,
  env?: NodeJS.ProcessEnv,
  _logger?: Logger,
): QuotaProvider {
  return {
    id: "anthropic",
    displayName: "Anthropic",
    category: "api-spend",
    authStrategy: "env",

    async isAvailable(_credentials?: unknown, _ctx?: unknown): Promise<boolean> {
      const effectiveConfig = config ?? (_credentials as QuotasConfig | undefined);
      const effectiveAuth = auth ?? (_credentials as Record<string, unknown> | undefined);
      const effectiveEnv = env ?? process.env;
      const cred = await credSrc.get("anthropic");
      if (!cred) return false;
      // orgId must be resolvable for fetchQuotas to succeed without throwing.
      // Lenient when effectiveConfig is undefined (config not available in call path).
      // Strict when effectiveConfig is present — attempt resolution regardless of anthropic field.
      if (!effectiveConfig) return true;
      try {
        resolveAnthropicOrgId(effectiveConfig, effectiveAuth, effectiveEnv);
        return true;
      } catch {
        return false;
      }
    },

    async fetchQuotas(_credentials?: unknown, _ctx?: unknown): Promise<QuotaData[]> {
      const effectiveConfig = config ?? (_credentials as QuotasConfig | undefined);
      const effectiveAuth = auth ?? (_credentials as Record<string, unknown> | undefined);
      const effectiveEnv = env ?? process.env;
      const cred = await credSrc.get("anthropic");
      if (!cred || cred?.variant !== "api") return [];
      const key = cred.key;
      // Config absent: orgId cannot be resolved → return [] (backward compat for direct calls).
      // Config present: always attempt resolution; throw if orgId missing (fail-fast).
      if (!effectiveConfig) return [];
      let orgId: string;
      try {
        orgId = resolveAnthropicOrgId(effectiveConfig, effectiveAuth, effectiveEnv);
      } catch {
        throw new Error(
          "Anthropic org_id not configured. Set anthropic.orgId in quotas.json, " +
          "anthropic.orgId (or org) in auth.json, or ANTHROPIC_ORG_ID env variable.",
        );
      }
      const baseUrl = USAGE_URL.replace("{org_id}", orgId);
      const rows: QuotaData[] = [];
      let nextPage: string | null = null;
      for (let page = 0; page < MAX_PAGES; page++) {
        const pageUrl = nextPage ? `${baseUrl}?page=${nextPage}` : baseUrl;
        let data: unknown;
        try {
          data = await http.request<unknown>(
            { url: pageUrl, method: "GET", headers: { "x-api-key": key, "anthropic-version": "2023-06-01" } },
            { timeoutMs: 15_000, retries: 0, redact: true },
          );
        } catch (err) {
          const status = (err as { status?: number }).status;
          // Admin scope required: 401 = key lacks scope, 403 = org restricts admin scope.
          // Fail fast so the user sees an actionable message instead of a silent [].
          if (status === 401 || status === 403) {
            throw new Error(
              "Anthropic admin-usage request denied (401/403). " +
              "Confirm your API key has the 'Admin API' organization usage read permission.",
            );
          }
          throw err;
        }
        if (!isObj(data)) break;
        const obj = data as Record<string, unknown>;
        const pageData = Array.isArray(obj.data) ? obj.data as Record<string, unknown>[] : [];
        for (let i = 0; i < pageData.length; i++) {
          const entry = mapRow(pageData[i], rows.length);
          if (entry) rows.push(entry);
        }
        if (!obj.has_more || !obj.next_page) break;
        nextPage = typeof obj.next_page === "string" ? obj.next_page : null;
        if (!nextPage) break;
      }
      return rows;
    },
  };
}
