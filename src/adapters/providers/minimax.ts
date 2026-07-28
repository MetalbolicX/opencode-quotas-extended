// Minimax Coding Plan provider — CLI-based (no HTTP endpoint).
// Credentials: key stored in auth.json under "minimax-coding-plan".
import { execSync } from "node:child_process";
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { windowMap } from "./coding-plan-parse.js";
import { enrichQuotaLabel, buildProviderName } from "../../rendering/semantic-labels.js";

interface MinimaxRemainsEntry {
  model_name: string;
  current_interval_total_count: number;
  current_interval_usage_count: number;
  current_interval_remaining_percent: number;
  current_weekly_total_count: number;
  current_weekly_usage_count: number;
  current_weekly_remaining_percent: number;
}

const extractJson = (out: string): string | null => {
  // mmx prints a human-readable table before the JSON blob; the first `[` is
  // inside the progress bar. Locate the unique `"model_remains"` key and
  // grab from the opening `{` before it.
  const idx = out.indexOf('"model_remains"');
  if (idx === -1) return null;
  const start = out.lastIndexOf("{", idx);
  return start === -1 ? null : out.slice(start);
};

const parseMinimaxCli = (out: string, _key: string): QuotaData[] => {
  const jsonText = extractJson(out);
  if (!jsonText) return [];
  let json: unknown;
  try { json = JSON.parse(jsonText); } catch { return []; }
  if (!json || typeof json !== "object") return [];
  const obj = json as Record<string, unknown>;
  const remains = Array.isArray(obj.model_remains)
    ? (obj.model_remains as MinimaxRemainsEntry[])
    : [];
  const entries: QuotaData[] = [];
  for (const m of remains) {
    const pct = m.current_interval_remaining_percent ?? 0;
    const dailyConcept = enrichQuotaLabel("minimax", { modelName: m.model_name, weekly: false });
    entries.push({
      id: `minimax-${m.model_name.toLowerCase()}-daily`,
      providerName: buildProviderName("Minimax", dailyConcept.concept),
      used: 100 - pct,
      limit: 100,
      unit: "%",
      window: "daily",
      reset: null,
      predictedReset: null,
      info: dailyConcept.label,
    });
    if (m.current_weekly_total_count > 0) {
      const weeklyConcept = enrichQuotaLabel("minimax", { modelName: m.model_name, weekly: true });
      entries.push({
        id: `minimax-${m.model_name.toLowerCase()}-weekly`,
        providerName: buildProviderName("Minimax", weeklyConcept.concept),
        used: m.current_weekly_usage_count,
        limit: m.current_weekly_total_count,
        unit: "requests",
        window: "rolling-weekly",
        reset: null,
        predictedReset: null,
        info: weeklyConcept.label,
      });
    }
  }
  return entries;
};

const MINIMAX_CLI_INSTALL_URL = "https://github.com/minimaxai/minimax-cli";

/**
 * Verifies `mmx` is present in PATH using the `which` lookup.
 * Throws if the binary is not found so callers can handle gracefully.
 */
const assertMmxBinary = (): void => {
  try {
    // `which` exits 0 + prints path on success; throws ENOENT on failure.
    execSync("which mmx", { stdio: "pipe" });
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === "ENOENT" || e.code === "127") {
      const msg = `\`mmx\` CLI not found in PATH. Install from ${MINIMAX_CLI_INSTALL_URL}`;
      throw new Error(msg);
    }
    // Rethrow unexpected child_process errors (e.g. EACCES, ENOTDIR).
    throw err;
  }
};

export function createMinimaxProvider(credSrc: CredentialSource, _http: HttpClient, _logger?: Logger): QuotaProvider {
  return {
    id: "minimax", displayName: "Minimax Coding Plan", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("minimax-coding-plan")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      const cred = await credSrc.get("minimax-coding-plan");
      if (!cred) return [];
      const key = cred.variant === "api" ? cred.key : null;
      if (!key) return [];

      // WU-6: pre-check mmx binary presence before attempting any subprocess call.
      // If missing, log a friendly error and return [] instead of crashing.
      try {
        assertMmxBinary();
      } catch (err) {
        _logger?.error("minimax: mmx binary not found", { error: String(err) });
        return [];
      }

      try {
        // Spawn mmx CLI — authenticate then fetch quota JSON.
        // stdout is clean JSON; stderr is progress/spinner noise (discarded).
        const { execSync } = await import("node:child_process");
        const escapedKey = key.replace(/'/g, "'\\''");
        const out = execSync(
          `mmx auth login --api-key '${escapedKey}' 2>/dev/null && mmx quota show --output json 2>/dev/null`,
          { timeout: 30_000 }
        ).toString("utf-8").trim();
        return parseMinimaxCli(out, key);
      } catch {
        return [];
      }
    },
  };
}
