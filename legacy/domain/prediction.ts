// Pure domain: zero I/O. Dual-window linear regression ETTL.
import type { HistoryPoint } from "./types.js";

interface PredictionParams {
  windowMinutes?: number;
  shortWindowMinutes?: number;
  now?: number;
  windowInfo?: string;
}

const LONG_WINDOW_MINUTES_DEFAULT = 60;
const SHORT_WINDOW_MINUTES_DEFAULT = 5;
const IDLE_TIMEOUT_MS = 5 * 60 * 1000;
const SHORT_WINDOW_FALLBACK_RATIO = 0.15;

const slope = (history: HistoryPoint[]): number => {
  if (history.length < 2) return 0;
  const n = history.length;
  const firstTs = history[0].timestamp;
  let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
  for (const p of history) {
    const x = p.timestamp - firstTs;
    const y = p.used;
    sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x;
  }
  const denom = n * sumX2 - sumX * sumX;
  if (denom === 0) return 0;
  return (n * sumXY - sumX * sumY) / denom;
}

const isLongTermWindow = (windowInfo: string | undefined): boolean => {
  return Boolean(windowInfo && /week|month|\d+d/i.test(windowInfo));
}

export const predictTimeToLimit = (
  history: readonly HistoryPoint[],
  params: PredictionParams = {}
): number => {
  const longWindowMs = (params.windowMinutes ?? LONG_WINDOW_MINUTES_DEFAULT) * 60 * 1000;
  const shortWindowMs = (params.shortWindowMinutes ?? SHORT_WINDOW_MINUTES_DEFAULT) * 60 * 1000;
  const now = params.now ?? Date.now();

  if (history.length < 2) return Infinity;

  const lastPoint = history[history.length - 1];
  if (now - lastPoint.timestamp > IDLE_TIMEOUT_MS) return Infinity;

  const windowed = history.filter(p => p.timestamp >= now - longWindowMs);
  const mLong = slope(windowed);
  if (mLong <= 0) return Infinity;

  let m = mLong;
  if (!isLongTermWindow(params.windowInfo)) {
    const shortHistory = windowed.filter(p => p.timestamp >= now - shortWindowMs);
    const effective = shortHistory.length >= 2
      ? shortHistory
      : history.slice(-Math.max(2, Math.ceil(history.length * SHORT_WINDOW_FALLBACK_RATIO)));
    const mShort = slope(effective);
    m = Math.max(mLong, mShort);
  }

  if (m <= 0) return Infinity;
  if (lastPoint.limit === null || lastPoint.limit <= 0) return Infinity;
  const remaining = lastPoint.limit - lastPoint.used;
  if (remaining <= 0) return 0;
  return Math.max(0, remaining / m - (now - lastPoint.timestamp));
}
