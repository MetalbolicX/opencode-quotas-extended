// RED → GREEN → REFACTOR: aggregation strategies + most_critical fallback.
import { describe, it, expect } from "vitest";
import {
  aggregate,
  aggregateMax,
  aggregateMin,
  aggregateMean,
  aggregateMedian,
  aggregateMostCritical,
} from "../../../src/domain/aggregation.js";
import type { QuotaData } from "../../../src/domain/types.js";

// ── helpers ────────────────────────────────────────────────────────────────────

const q = (
  id: string,
  used: number,
  limit: number,
  providerName = "test",
  window: QuotaData["window"] = "daily",
): QuotaData =>
  Object.freeze({ id, providerName, used, limit, unit: "requests", reset: null, window });

const ETTL_MAP = Object.freeze({
  "a": 10,
  "b": 20,
  "c": 30,
});

describe("aggregateMostCritical", () => {
  describe("most_critical with history picks shortest ETTL member", () => {
    it("picks member with smallest ETTL", () => {
      const quotas = [q("a", 50, 100), q("b", 50, 100), q("c", 50, 100)];
      const result = aggregateMostCritical(quotas, ETTL_MAP);
      expect(result?.id).toBe("a"); // ETTL 10 < 20 < 30
    });

    it("returns null for empty array", () => {
      const result = aggregateMostCritical([], ETTL_MAP);
      expect(result).toBeNull();
    });

    it("falls back to aggregateMax when ETTL map is empty", () => {
      const quotas = [q("a", 80, 100), q("b", 50, 100)];
      const result = aggregateMostCritical(quotas, {});
      expect(result?.id).toBe("a"); // highest ratio = 0.8 vs 0.5
    });
  });

  describe("most_critical without history returns first member without throwing", () => {
    it("returns first member when no ETTL history exists", () => {
      const quotas = Object.freeze([q("x", 40, 80), q("y", 60, 80), q("z", 20, 80)]);
      // No ETTL map — all members have Infinity
      const result = aggregateMostCritical(quotas, {});
      // Fallback returns first member without throwing
      expect(result).not.toBeNull();
      expect(result?.id).toBe("x"); // first member returned
    });

    it("does not throw when ettlMap is undefined", () => {
      const quotas = Object.freeze([q("a", 10, 20)]);
      // TypeScript: passing undefined for ettlMap uses default {}
      const result = aggregateMostCritical(quotas, undefined as unknown as Record<string, number>);
      expect(result?.id).toBe("a");
    });

    it("returns null for empty quotas regardless of ettlMap", () => {
      const result = aggregateMostCritical([], { "a": 10 });
      expect(result).toBeNull();
    });
  });
});

describe("aggregateMax", () => {
  it("returns null for empty array", () => {
    expect(aggregateMax([])).toBeNull();
  });

  it("returns the item with highest used/limit ratio", () => {
    const quotas = [q("a", 50, 100), q("b", 90, 100), q("c", 30, 100)];
    expect(aggregateMax(quotas)?.id).toBe("b");
  });

  it("treats null limit as 0 ratio", () => {
    const quotas: readonly QuotaData[] = [q("a", 50, null!), q("b", 10, 100)];
    expect(aggregateMax(quotas)?.id).toBe("b");
  });
});

describe("aggregateMin", () => {
  it("returns null for empty array", () => {
    expect(aggregateMin([])).toBeNull();
  });

  it("returns the item with lowest used/limit ratio", () => {
    const quotas = [q("a", 50, 100), q("b", 10, 100), q("c", 90, 100)];
    expect(aggregateMin(quotas)?.id).toBe("b");
  });
});

describe("aggregateMean", () => {
  it("returns an aggregated QuotaData with avg ratio", () => {
    const quotas = [q("a", 50, 100), q("b", 100, 100)];
    const result = aggregateMean(quotas, "Avg", "agg-mean");
    expect(result.id).toBe("agg-mean");
    expect(result.providerName).toBe("Avg");
    expect(result.used).toBe(75); // (0.5 + 1.0) / 2 * 100
    expect(result.limit).toBe(100);
  });
});

describe("aggregateMedian", () => {
  it("returns null for empty array", () => {
    expect(aggregateMedian([])).toBeNull();
  });

  it("returns middle item by ratio (synthetic object, like aggregateMean)", () => {
    const quotas = [q("a", 10, 100), q("b", 50, 100), q("c", 90, 100)];
    const result = aggregateMedian(quotas);
    // Returns a synthetic object with id="agg-median" (like aggregateMean)
    expect(result?.id).toBe("agg-median");
    expect(result?.used).toBe(50); // median ratio of [0.1, 0.5, 0.9] = 0.5 → 50
  });
});

describe("aggregate dispatcher", () => {
  it("routes to most_critical", () => {
    const quotas = [q("a", 50, 100), q("b", 80, 100)];
    const result = aggregate(quotas, "most_critical", { a: 5, b: 15 });
    expect(result?.id).toBe("a");
  });

  it("routes to max", () => {
    const quotas = [q("a", 20, 100), q("b", 80, 100)];
    expect(aggregate(quotas, "max")?.id).toBe("b");
  });

  it("routes to min", () => {
    const quotas = [q("a", 20, 100), q("b", 80, 100)];
    expect(aggregate(quotas, "min")?.id).toBe("a");
  });

  it("routes to mean", () => {
    const quotas = [q("a", 50, 100), q("b", 100, 100)];
    expect(aggregate(quotas, "mean")?.id).toBe("agg-mean");
  });

  it("routes to median", () => {
    const quotas = [q("a", 10, 100), q("b", 50, 100), q("c", 90, 100)];
    // aggregateMedian returns synthetic id (like aggregateMean)
    expect(aggregate(quotas, "median")?.id).toBe("agg-median");
    expect(aggregate(quotas, "median")?.used).toBe(50);
  });
});
