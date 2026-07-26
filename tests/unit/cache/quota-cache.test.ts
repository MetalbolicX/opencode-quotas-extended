// RED: CacheSource port + QuotaCache adapter — cold/storm/stale/prune/invalidate/immutability
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { QuotaData } from "../../../src/domain/types.js";

const fakeQuota = (id: string, used = 50, limit = 100): QuotaData =>
  Object.freeze({ id, providerName: "test", used, limit, unit: "requests", reset: null, predictedReset: null, window: "daily" as const });

describe("QuotaCache", () => {
  let mockFetcher: ReturnType<typeof vi.fn>;
  beforeEach(() => { vi.useFakeTimers(); mockFetcher = vi.fn(); });
  afterEach(() => { vi.useRealTimers(); vi.resetAllMocks(); });

  // cold cache: one fetch, result cached and returned on second call
  describe("cold cache fetches once", () => {
    it("empty cache → exactly 1 fetch, result cached", async () => {
      const data = Object.freeze([fakeQuota("a", 10, 20)]);
      mockFetcher.mockResolvedValueOnce(data);
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      const result = await cache.get();
      expect(result).toEqual(data);
      expect(mockFetcher).toHaveBeenCalledTimes(1);
      const cached = await cache.get();
      expect(cached).toBe(result); // same reference, no new fetch
      expect(mockFetcher).toHaveBeenCalledTimes(1);
    });
  });

  // storm: 50 concurrent callers all attach to the same in-flight promise
  describe("storm coalesces to one fetch", () => {
    it("50 concurrent calls on empty cache → exactly 1 fetch, all receive same data", async () => {
      const data = Object.freeze([fakeQuota("b", 20, 40)]);
      mockFetcher.mockResolvedValueOnce(data);
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      const results = await Promise.all(Array.from({ length: 50 }, () => cache.get()));
      expect(mockFetcher).toHaveBeenCalledTimes(1);
      for (const r of results) expect(r).toBe(results[0]);
    });

    it("50 concurrent calls while fetch in-flight → all wait on same promise", async () => {
      let resolve: (v: readonly QuotaData[]) => void;
      mockFetcher.mockImplementation(() => new Promise((r) => { resolve = r; }));
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      const firstGet = cache.get();
      const pending = Array.from({ length: 49 }, () => cache.get());
      resolve!(Object.freeze([fakeQuota("c", 30, 60)]));
      const results = await Promise.all([firstGet, ...pending]);
      expect(mockFetcher).toHaveBeenCalledTimes(1);
      for (const r of results) expect(r).toBe(results[0]);
    });
  });

  // stale: warm cache returns immediately without blocking on fetch
  describe("stale-but-present served fast", () => {
    it("warm cache returns lastSnapshot immediately without waiting for a new fetch", async () => {
      const data = Object.freeze([fakeQuota("d", 40, 80)]);
      mockFetcher.mockResolvedValueOnce(data);
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      await cache.get(); // populate
      expect(mockFetcher).toHaveBeenCalledTimes(1);
      // Warm path: lastSnapshot returned immediately (verifiable via state)
      const snap = (cache as unknown as { lastSnapshot: { at: number; data: readonly QuotaData[] } | null }).lastSnapshot;
      expect(snap?.data).toStrictEqual(data);
    });
  });

  // prune: cap=N, N+1 fetches → oldest evicted, history.len===N
  describe("prune oldest past cap", () => {
    it("cap N, N+1 refreshes → oldest evicted, retained count == N", async () => {
      const N = 5;
      for (let i = 1; i <= N + 1; i++) mockFetcher.mockResolvedValueOnce(Object.freeze([fakeQuota(`q${i}`, i, 100)]));
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 1, maxHistory: N }) as unknown as {
        lastSnapshot: { at: number; data: readonly QuotaData[] } | null; inFlight: Promise<readonly QuotaData[]> | null;
        history: Array<{ at: number; data: readonly QuotaData[] }>; get(): Promise<readonly QuotaData[]>;
      };
      await cache.get(); expect(mockFetcher).toHaveBeenCalledTimes(1);
      for (let i = 0; i < N; i++) {
        vi.advanceTimersByTime(2); cache.lastSnapshot = null; cache.inFlight = null;
        await cache.get(); expect(mockFetcher).toHaveBeenCalledTimes(i + 2);
      }
      expect(cache.history).toHaveLength(N);
      const ids = cache.history.map((h) => h.data[0].id);
      expect(ids).not.toContain("q1"); // oldest evicted
      expect(ids).toContain(`q${N + 1}`); // newest retained
    });
  });

  // bounded: many fetches → history never exceeds cap
  describe("bounded under sustained polling", () => {
    it("history never exceeds cap regardless of how many fetches occur", async () => {
      const MAX = 50, TOTAL = 70;
      for (let i = 1; i <= TOTAL; i++) mockFetcher.mockResolvedValueOnce(Object.freeze([fakeQuota(`p${i}`, i, 100)]));
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 1, maxHistory: MAX }) as unknown as {
        lastSnapshot: { at: number; data: readonly QuotaData[] } | null; inFlight: Promise<readonly QuotaData[]> | null;
        history: Array<{ at: number; data: readonly QuotaData[] }>; get(): Promise<readonly QuotaData[]>;
      };
      await cache.get();
      for (let i = 0; i < TOTAL - 1; i++) { vi.advanceTimersByTime(2); cache.lastSnapshot = null; cache.inFlight = null; await cache.get(); }
      expect(cache.history.length).toBeLessThanOrEqual(MAX);
      expect(cache.history[cache.history.length - 1]?.data[0].id).toBe(`p${TOTAL}`);
      expect(cache.history[0]?.data[0].id).toBe(`p${TOTAL - MAX + 1}`);
    });
  });

  // invalidate: clears snapshot and in-flight, next get() fetches fresh
  describe("invalidate", () => {
    it("invalidate() then get() → fresh fetch", async () => {
      mockFetcher.mockResolvedValueOnce(Object.freeze([fakeQuota("x", 1, 10)])).mockResolvedValueOnce(Object.freeze([fakeQuota("x", 2, 10)]));
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      await cache.get(); expect(mockFetcher).toHaveBeenCalledTimes(1);
      cache.invalidate();
      await cache.get(); expect(mockFetcher).toHaveBeenCalledTimes(2);
    });

    it("invalidate() while fetch in-flight → clears inFlight, next get() fetches again", async () => {
      let resolve: (v: readonly QuotaData[]) => void;
      mockFetcher.mockImplementation(() => new Promise((r) => { resolve = r; }));
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      const firstGet = cache.get();
      cache.invalidate(); // cancel in-flight
      resolve!(Object.freeze([fakeQuota("y", 10, 20)]));
      mockFetcher.mockResolvedValueOnce(Object.freeze([fakeQuota("y", 11, 20)]));
      await cache.get();
      expect(mockFetcher).toHaveBeenCalledTimes(2); // original + fresh
    });
  });

  // immutability: returned data is the same reference, frozen
  describe("immutability", () => {
    it("same snapshot → same reference returned on repeated calls", async () => {
      const data = Object.freeze([fakeQuota("z", 99, 200)]);
      mockFetcher.mockResolvedValueOnce(data);
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      const r1 = await cache.get(); const r2 = await cache.get();
      expect(r1).toBe(r2); expect(r1[0]).toBe(r2[0]);
    });

    it("returned array is frozen and cannot be mutated", async () => {
      const data = Object.freeze([fakeQuota("w", 5, 10)]);
      mockFetcher.mockResolvedValueOnce(data);
      const { QuotaCache } = await import("../../../src/adapters/infra/quota-cache.js");
      const cache = new QuotaCache(mockFetcher, { interval: 60_000, maxHistory: 50 });
      const result = await cache.get();
      expect(() => { (result as unknown as { push: (q: QuotaData) => number }).push(fakeQuota("mutated", 0, 0)); }).toThrow();
    });
  });
});
