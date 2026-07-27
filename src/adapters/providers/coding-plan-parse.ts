// Shared parsing helpers for coding-plan providers.
import type { QuotaData } from "../../domain/types.js";

export function toNum(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const p = Number.parseFloat(v); if (Number.isFinite(p)) return p; }
  return null;
}

/** Normalizes free-form window labels to the strict domain union. */
export function windowMap(label: string | undefined): "daily" | "monthly" | "rolling" {
  if (!label) return "rolling";
  const l = label.toLowerCase().trim();
  if (l.includes("daily")) return "daily";
  if (l.includes("monthly") || l.includes("month")) return "monthly";
  if (l.includes("weekly") || l.includes("week")) return "rolling";
  if (l.includes("hour") || /\d+\s*h/.test(l)) return "rolling";
  return "rolling";
}

export function parseUsage(json: unknown, idPrefix: string, providerName: string): QuotaData[] {
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
 * Parses the z.ai `/api/monitor/usage/quota/limit` envelope.
 * Shape: { code, msg, data: { limits: Array<{type, unit, number, usage, currentValue, remaining, percentage, nextResetTime, usageDetails}> } }
 */
export function parseZaiLimits(json: unknown, idPrefix: string, providerName: string): QuotaData[] {
  const data = (json as { data?: unknown })?.data;
  const limits = Array.isArray((data as { limits?: unknown })?.limits)
    ? (data as { limits: Array<Record<string, unknown>> }).limits
    : [];
  if (limits.length === 0) return [];

  const entries: QuotaData[] = [];
  for (const l of limits) {
    const used = toNum(l.currentValue);
    const limit = toNum(l.usage);
    if (used === null && limit === null) continue;

    const type = String(l.type ?? "LIMIT").toLowerCase();
    const unit = toNum(l.unit);
    const num = toNum(l.number);
    const id = `${idPrefix}-${type}-${unit ?? "u"}-${num ?? "n"}`;
    const label = `${l.type ?? "Limit"}${unit !== null ? ` (${num ?? "?"}×${unit})` : ""}`;
    const resetMs = toNum(l.nextResetTime);

    entries.push({
      id,
      providerName: `${providerName} ${label}`,
      used: used ?? 0,
      limit,
      unit: "%",
      window: windowMap(type),
      reset: resetMs ? new Date(resetMs) : null,
      predictedReset: null,
      info: `${providerName} ${label}`,
    });
  }
  return entries;
}
