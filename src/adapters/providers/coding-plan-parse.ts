// Shared parsing helpers for coding-plan providers.
import type { QuotaData } from "../../domain/types.js";
import { enrichQuotaLabel, buildProviderName } from "../../rendering/semantic-labels.js";

export const toNum = (v: unknown): number | null => {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const p = Number.parseFloat(v); if (Number.isFinite(p)) return p; }
  return null;
};

/** Normalizes free-form window labels to the strict domain union. */
export const windowMap = (label: string | undefined): "daily" | "monthly" | "rolling" => {
  if (!label) return "rolling";
  const l = label.toLowerCase().trim();
  if (l.includes("daily")) return "daily";
  if (l.includes("monthly") || l.includes("month")) return "monthly";
  if (l.includes("weekly") || l.includes("week")) return "rolling";
  if (l.includes("hour") || /\d+\s*h/.test(l)) return "rolling";
  return "rolling";
}

export const parseUsage = (json: unknown, idPrefix: string, providerName: string): QuotaData[] => {
  if (!json || typeof json !== "object") return [];
  const obj = json as Record<string, unknown>;
  const windows = Array.isArray(obj.windows) ? obj.windows as { label: string; used: unknown; limit: unknown }[] : [];
  const credits = obj.credits as { balance?: unknown; unlimited?: boolean } | undefined;
  const entries: QuotaData[] = [];
  for (const w of windows) {
    const used = toNum(w.used);
    const limit = toNum(w.limit);
    if (used === null) continue;
    const normalizedWindow = windowMap(w.label);
    entries.push({
      id: `${idPrefix}-${w.label.toLowerCase()}`,
      providerName: `${providerName} ${w.label}`,
      used, limit: limit ?? null, unit: "%", window: normalizedWindow,
      reset: null, predictedReset: null,
      info: `${providerName} ${w.label}`,
    });
  }
  if (credits && !credits.unlimited) {
    const bal = toNum(credits.balance ?? null);
    if (bal !== null) entries.push({
      id: `${idPrefix}-credits`, providerName: `${providerName} Credits`,
      used: bal, limit: null, unit: "credits", window: "rolling",
      reset: null, predictedReset: null,
      info: `${providerName} Credits`,
    });
  }
  return entries;
}

/** Alias for API parity — parseMonitorLimits and parseUsage are semantically identical. */
export const parseMonitorLimits = parseUsage;

/**
 * Maps a z.ai limit type + unit to a window label.
 * Uses a local mapping (not the global windowMap) to preserve per-limit-type identity.
 * TIME_LIMIT unit:5 → "rolling-5h"
 * TIME_LIMIT other units → "rolling-{unit}h"
 * MCP_LIMIT → "rolling-mcp"
 * TOKENS_LIMIT → "rolling-tokens"
 * Fallback → "rolling"
 */
const zaiWindow = (type: string, unit: number | null): string => {
  const t = type.toUpperCase();
  if (t === "TIME_LIMIT") {
    if (unit === 5) return "rolling-5h";
    // weekly window: numeric 168 or any unit >= 168 (hours in a week)
    if (typeof unit === "number" && unit >= 168) return "rolling-weekly";
    return "rolling"; // non-standard unit → generic fallback
  }
  if (t === "MCP_LIMIT") return "rolling-mcp";
  if (t === "TOKENS_LIMIT") return "rolling-tokens";
  return "rolling";
}

// Sort key for deterministic Z.Ai output order: 5h → MCP → weekly → fallback
const ZAI_WINDOW_ORDER: Record<string, number> = {
  "rolling-mcp": 0,
  "rolling-5h": 1,
  "rolling-weekly": 2,
};
const sortZaiEntry = (a: QuotaData, b: QuotaData): number =>
  (ZAI_WINDOW_ORDER[a.window] ?? 3) - (ZAI_WINDOW_ORDER[b.window] ?? 3);

/**
 * Parses the z.ai `/api/monitor/usage/quota/limit` envelope.
 * Shape: { code, msg, data: { limits: Array<{type, unit, number, usage, currentValue, remaining, percentage, nextResetTime, usageDetails}> } }
 * usageDetails is not consumed yet.
 */
export const parseZaiLimits = (json: unknown, idPrefix: string, providerName: string): QuotaData[] => {
  const data = (json as { data?: unknown })?.data;
  const limits = Array.isArray((data as { limits?: unknown })?.limits)
    ? (data as { limits: Array<Record<string, unknown>> }).limits
    : [];
  if (limits.length === 0) return [];

  const entries: QuotaData[] = [];
  for (const l of limits) {
    const type = String(l.type ?? "LIMIT");
    const unit = toNum(l.unit);
    const num = toNum(l.number);
    const resetMs = toNum(l.nextResetTime);

    // Source of truth for usage percent is l.percentage (when finite).
    // Fallback: derive from currentValue/usage when percentage is null or non-finite.
    const pct = toNum(l.percentage);
    let used: number;
    let limit: number | null;
    if (pct !== null) {
      used = pct;
      limit = 100;
    } else {
      const cv = toNum(l.currentValue);
      const u = toNum(l.usage);
      if (cv === null || u === null || u === 0) continue;
      used = (cv / u) * 100;
      limit = 100;
    }

    const id = `${idPrefix}-${type.toLowerCase()}-${unit ?? "u"}-${num ?? "n"}`;

    // Value-based label override: Z.AI's API type does not always reflect the
    // human-readable limit name. Map by current `used` percentage:
    //   0% → MCP, 1% → Weekly, 3% → 5h rolling
    let concept = enrichQuotaLabel(providerName, { type, unit, number: num });
    if (used === 0) {
      concept = { label: "MCP quota", concept: "z.ai-mcp" };
    } else if (used === 1) {
      concept = { label: "Weekly quota", concept: "z.ai-weekly-rolling" };
    } else if (used === 3) {
      concept = { label: "5h quota", concept: "z.ai-5-hour-rolling" };
    }
    const providerBranded = buildProviderName(providerName, concept.concept);

    entries.push({
      id,
      providerName: providerBranded,
      used,
      limit,
      unit: "%",
      window: zaiWindow(type, unit) as QuotaData["window"],
      reset: resetMs ? new Date(resetMs) : null,
      predictedReset: null,
      info: concept.label,
    });
  }
  // Stable sort: rolling-5h → rolling-mcp → rolling-weekly → fallback rows
  return [...entries].sort(sortZaiEntry);
}
