// Pure domain: reset detection — ≥20% drop from peak triggers a reset signal.
import type { HistoryPoint, QuotaData } from "./types.js";

const RESET_THRESHOLD_PERCENT = 20;

export function detectReset(
  lastPoint: HistoryPoint,
  current: QuotaData
): boolean {
  if (lastPoint.limit === null || lastPoint.limit <= 0) return false;
  if (current.limit === null || current.limit <= 0) return false;
  const drop = lastPoint.used - current.used;
  if (drop <= 0) return false;
  const threshold = (RESET_THRESHOLD_PERCENT / 100) * current.limit;
  return drop >= threshold;
}
