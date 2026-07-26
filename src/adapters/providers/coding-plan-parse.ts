// Shared parsing helpers for coding-plan providers.
import type { QuotaData } from "../../domain/types.js";

export function toNum(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const p = Number.parseFloat(v); if (Number.isFinite(p)) return p; }
  return null;
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
    entries.push({
      id: `${idPrefix}-${w.label.toLowerCase()}`,
      providerName: `${providerName} ${w.label}`,
      used, limit: limit ?? null, unit: "%", window: "rolling",
      reset: null, predictedReset: null,
    });
  }
  if (credits && !credits.unlimited) {
    const bal = toNum(credits.balance ?? null);
    if (bal !== null) entries.push({ id: `${idPrefix}-credits`, providerName: `${providerName} Credits`, used: bal, limit: null, unit: "credits", window: "rolling", reset: null, predictedReset: null });
  }
  return entries;
}
