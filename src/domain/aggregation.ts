// Pure domain: zero I/O, zero Node built-ins, zero adapter imports.
import type { QuotaData } from "./types.js";

// ── ratio helper ──────────────────────────────────────────────────────────────
const ratio = (q: QuotaData): number =>
  q.limit !== null && q.limit > 0 ? q.used / q.limit : 0;

// ── strategies ────────────────────────────────────────────────────────────────
export function aggregateMax(quotas: readonly QuotaData[]): QuotaData | null {
  if (quotas.length === 0) return null;
  return quotas.reduce((a, b) => (ratio(a) > ratio(b) ? a : b));
}

export function aggregateMin(quotas: readonly QuotaData[]): QuotaData | null {
  if (quotas.length === 0) return null;
  return quotas.reduce((a, b) => (ratio(a) < ratio(b) ? a : b));
}

export function aggregateMean(
  quotas: readonly QuotaData[],
  name = "Aggregated",
  id = "agg-mean"
): QuotaData {
  const avgRatio =
    quotas.reduce((s, q) => s + ratio(q), 0) / Math.max(1, quotas.length);
  return { id, providerName: name, used: Math.round(avgRatio * 100), limit: 100, unit: "%", reset: null, predictedReset: null, window: "rolling" };
}

export function aggregateMedian(
  quotas: readonly QuotaData[],
  name = "Aggregated",
  id = "agg-median"
): QuotaData {
  const sorted = [...quotas].sort((a, b) => ratio(a) - ratio(b));
  const mid = sorted[Math.floor(sorted.length / 2)];
  return { id, providerName: name, used: Math.round(ratio(mid) * 100), limit: 100, unit: "%", reset: null, predictedReset: null, window: "rolling" };
}

export function aggregateMostCritical(
  quotas: readonly QuotaData[],
  ettlMap: Record<string, number>
): QuotaData | null {
  if (quotas.length === 0) return null;
  let best: QuotaData | null = null;
  let minTime = Infinity;
  for (const q of quotas) {
    const t = ettlMap[q.id] ?? Infinity;
    if (t < minTime) { minTime = t; best = q; }
  }
  if (!best) return aggregateMax(quotas);
  if (minTime === Infinity) return best;
  return best;
}

// ── dispatcher ────────────────────────────────────────────────────────────────
export type AggregationStrategy = "most_critical" | "max" | "min" | "mean" | "median";

export function aggregate(
  quotas: readonly QuotaData[],
  strategy: AggregationStrategy,
  ettlMap?: Record<string, number>
): QuotaData | null {
  switch (strategy) {
    case "most_critical": return aggregateMostCritical(quotas, ettlMap ?? {});
    case "max":           return aggregateMax(quotas);
    case "min":           return aggregateMin(quotas);
    case "mean":          return aggregateMean(quotas);
    case "median":        return aggregateMedian(quotas);
  }
}
