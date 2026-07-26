// RED → GREEN: locks in aggregation + prediction + reset parity against reference fixtures.
// Pure domain modules: aggregation.ts, prediction.ts, reset.ts — zero I/O.

import { describe, it, expect } from "vitest";
import aggFIXTURES from "../fixtures/reference/aggregation.json";
import predFIXTURES from "../fixtures/reference/prediction.json";
import resetFIXTURES from "../fixtures/reference/history-reset.json";

type QuotaData = { id: string; providerName: string; used: number; limit: number | null; unit: string; reset: null; predictedReset: null; window: "daily" | "monthly" | "rolling"; info?: string };
type HistoryPoint = { timestamp: number; used: number; limit: number | null };

const loadDomain = () => import("../../src/domain");

// ── aggregation ───────────────────────────────────────────────────────────────
describe("aggregation parity", () => {
  describe("most_critical", () => {
    it.each((aggFIXTURES.strategies as Record<string, { cases: unknown[] }>).most_critical.cases as { id: string; quotas: QuotaData[]; ettlMap: Record<string, number>; expected: { id: string } | null }[])(
      "$id", async ({ quotas, ettlMap, expected }) => {
        const { aggregateMostCritical } = await loadDomain();
        const result = aggregateMostCritical(quotas, ettlMap);
        expected === null ? expect(result).toBeNull() : expect(result?.id).toBe(expected.id);
      }
    );
  });
  describe("max", () => {
    it.each((aggFIXTURES.strategies as Record<string, { cases: unknown[] }>).max.cases as { id: string; quotas: QuotaData[]; expected: { id: string } }[])(
      "$id", async ({ quotas, expected }) => {
        const { aggregateMax } = await loadDomain();
        const r = aggregateMax(quotas);
        expect(r?.id).toBe(expected.id);
      }
    );
  });
  describe("min", () => {
    it.each((aggFIXTURES.strategies as Record<string, { cases: unknown[] }>).min.cases as { id: string; quotas: QuotaData[]; expected: { id: string } }[])(
      "$id", async ({ quotas, expected }) => {
        const { aggregateMin } = await loadDomain();
        expect(aggregateMin(quotas)?.id).toBe(expected.id);
      }
    );
  });
  describe("mean", () => {
    it.each((aggFIXTURES.strategies as Record<string, { cases: unknown[] }>).mean.cases as { id: string; quotas: QuotaData[]; expected: { used: number } }[])(
      "$id", async ({ quotas, expected }) => {
        const { aggregateMean } = await loadDomain();
        expect(aggregateMean(quotas).used).toBe(expected.used);
      }
    );
  });
  describe("median", () => {
    it.each((aggFIXTURES.strategies as Record<string, { cases: unknown[] }>).median.cases as { id: string; quotas: QuotaData[]; expected: { used: number } }[])(
      "$id", async ({ quotas, expected }) => {
        const { aggregateMedian } = await loadDomain();
        expect(aggregateMedian(quotas).used).toBe(expected.used);
      }
    );
  });
});

// ── prediction ─────────────────────────────────────────────────────────────────
describe("prediction parity", () => {
  it.each(predFIXTURES.cases as { id: string; history: HistoryPoint[]; now: number; params: { windowMinutes: number; shortWindowMinutes: number }; windowInfo: string; expected: { status: string } }[])(
    "$id", async ({ history, now, params, windowInfo, expected }) => {
      const { predictTimeToLimit } = await loadDomain();
      const r = predictTimeToLimit(history, { ...params, now, windowInfo });
      const status = r === Infinity ? "infinity" : r === 0 ? "zero" : "finite";
      expect(status).toBe(expected.status);
    }
  );
});

// ── reset ──────────────────────────────────────────────────────────────────────
describe("history reset parity", () => {
  it.each(resetFIXTURES.cases as { id: string; lastPoint: HistoryPoint; current: QuotaData; expected: boolean }[])(
    "$id", async ({ lastPoint, current, expected }) => {
      const { detectReset } = await loadDomain();
      expect(detectReset(lastPoint, current)).toBe(expected);
    }
  );
});
