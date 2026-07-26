// Minimax Coding Plan provider — CLI-based (no HTTP endpoint).
// Credentials: key stored in auth.json under "minimax-coding-plan".
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { QuotaProvider } from "../../ports/provider.js";
import type { QuotaData } from "../../domain/types.js";
import { windowMap } from "./coding-plan-parse.js";

interface MinimaxRemainsEntry {
  model_name: string;
  current_interval_total_count: number;
  current_interval_usage_count: number;
  current_interval_remaining_percent: number;
  current_weekly_total_count: number;
  current_weekly_usage_count: number;
  current_weekly_remaining_percent: number;
}

function parseMinimaxCli(out: string, _key: string): QuotaData[] {
  let json: unknown;
  try { json = JSON.parse(out); } catch { return []; }
  if (!json || typeof json !== "object") return [];
  const obj = json as Record<string, unknown>;
  const remains = Array.isArray(obj.model_remains)
    ? (obj.model_remains as MinimaxRemainsEntry[])
    : [];
  const entries: QuotaData[] = [];
  for (const m of remains) {
    const pct = m.current_interval_remaining_percent ?? 0;
    entries.push({
      id: `minimax-${m.model_name.toLowerCase()}-daily`,
      providerName: `Minimax ${m.model_name} Daily`,
      used: 100 - pct,
      limit: 100,
      unit: "%",
      window: windowMap(m.model_name.toLowerCase().includes("video") ? "daily" : "daily"),
      reset: null,
      predictedReset: null,
      info: `Minimax ${m.model_name}`,
    });
    if (m.current_weekly_total_count > 0) {
      entries.push({
        id: `minimax-${m.model_name.toLowerCase()}-weekly`,
        providerName: `Minimax ${m.model_name} Weekly`,
        used: m.current_weekly_usage_count,
        limit: m.current_weekly_total_count,
        unit: "requests",
        window: windowMap("weekly"),
        reset: null,
        predictedReset: null,
        info: `Minimax ${m.model_name} Weekly`,
      });
    }
  }
  return entries;
}

export function createMinimaxProvider(credSrc: CredentialSource, _http: HttpClient): QuotaProvider {
  return {
    id: "minimax", displayName: "Minimax Coding Plan", category: "subscription", authStrategy: "oauth",
    async isAvailable() { return (await credSrc.get("minimax-coding-plan")) !== null; },
    async fetchQuotas(): Promise<QuotaData[]> {
      const cred = await credSrc.get("minimax-coding-plan");
      if (!cred) return [];
      const key = cred.variant === "api" ? cred.key : null;
      if (!key) return [];
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
