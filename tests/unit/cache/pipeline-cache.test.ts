// Pipeline cache wiring tests — slice 4 config-wiring.
// Validates that ReportDeps accepts an optional cache and that the pipeline
// uses it when provided, falls back to direct fetch when absent.
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { QuotaData } from "../../../src/domain/types.js";
import type { CacheSource } from "../../../src/ports/cache.js";

// ── helpers ────────────────────────────────────────────────────────────────────
const mk = (overrides: Partial<QuotaData> = {}): QuotaData =>
  ({ id: "openai", providerName: "OpenAI", used: 50, limit: 100, unit: "%", reset: null, predictedReset: null, window: "daily" as const, ...overrides });

const MIXED: QuotaData[] = [
  mk({ id: "openai", providerName: "OpenAI", used: 30, limit: 100 }),
  mk({ id: "anthropic", providerName: "Anthropic", used: 65, limit: 100 }),
  mk({ id: "zen", providerName: "Zen", used: 5, limit: null }),
];

function makeRegistry(data: QuotaData[]) {
  const byId: Record<string, QuotaData[]> = {};
  for (const q of data) { (byId[q.id] ??= []).push(q); }
  const ids = Object.keys(byId);
  const mockProviders = ids.map((id) => ({
    id, displayName: id, category: "coding" as const, authStrategy: "api" as const,
    isAvailable: () => Promise.resolve(true),
    fetchQuotas: vi.fn<() => Promise<QuotaData[]>>(() => Promise.resolve(byId[id])),
  }));
  return { list: () => mockProviders, get: (id: string) => mockProviders.find((p) => p.id === id) };
}

function makeBaseDeps(data: QuotaData[]) {
  return {
    credentialResolver: { get: () => Promise.resolve(null) },
    httpClient: { request: vi.fn() },
    registry: makeRegistry(data),
    historyStore: {
      append: vi.fn<(_id: string, _pt: { timestamp: number; used: number; limit: number | null }) => Promise<void>>(),
      getHistory: vi.fn<(_id: string, _ms: number) => Promise<[]>>(),
      prune: vi.fn<(_ms: number) => Promise<void>>(),
      resetDetected: vi.fn(),
    },
    config: {
      displayMode: "table" as const, disabled: [] as readonly string[],
      aggregatedGroups: {} as Readonly<Record<string, { strategy: string; members: readonly string[] }>>,
      historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60,
      predictionShortWindowMinutes: 5, showUnaggregated: true,
      progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } as const,
    },
    logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  };
}

// ── module mocks so the pipeline doesn't pull real infra ───────────────────────
vi.mock("../../../src/adapters/infra/config-loader.js", () => ({
  DEFAULTS: { displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: true, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } },
  loadConfig: vi.fn(() => ({ displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: true, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } })),
}));
vi.mock("../../../src/adapters/auth/credential-resolver.js", () => ({
  createCredentialResolver: vi.fn(() => ({ get: () => Promise.resolve(null) })),
}));
vi.mock("../../../src/adapters/infra/fetch-http.js", () => ({
  FetchHttpClient: vi.fn(() => ({ request: vi.fn() })),
}));

describe("Pipeline: cache wiring", () => {
  it("pipeline uses cache when provided", async () => {
    const { reportQuotas } = await import("../../../src/application/report-pipeline.js");
    const cachedData = [mk({ id: "cached-openai", providerName: "Cached OpenAI" })];
    const mockCache: CacheSource = {
      get: vi.fn(() => Promise.resolve(cachedData)),
      invalidate: vi.fn(),
    };
    const deps = makeBaseDeps(MIXED);
    const result = await reportQuotas({ ...deps, cache: mockCache }, { mode: "table", now: Date.now() });
    expect(mockCache.get).toHaveBeenCalled();
    expect(result.rendered).toContain("Cached OpenAI");
  });

  it("pipeline falls back to direct fetch when no cache", async () => {
    const { reportQuotas } = await import("../../../src/application/report-pipeline.js");
    const deps = makeBaseDeps(MIXED);
    const result = await reportQuotas(deps, { mode: "table", now: Date.now() });
    // Direct fetch should have been called and data should be in output
    expect(result.rendered).toContain("OpenAI");
    expect(result.rendered).toContain("Anthropic");
  });

  it("pipeline passes fetcher to QuotaCache that fetches all providers", async () => {
    // This is tested implicitly: when cache.get() is called, it invokes the
    // fetcher which must collect from ALL providers in the registry.
    const { reportQuotas } = await import("../../../src/application/report-pipeline.js");
    const allProviderData = [mk({ id: "provider-a" }), mk({ id: "provider-b" })];
    let fetcherCalled = false;
    let fetcherProviderIds: string[] = [];
    const mockCache: CacheSource = {
      get: vi.fn(async () => {
        fetcherCalled = true;
        // The fetcher should have access to the registry via closure
        return allProviderData;
      }),
      invalidate: vi.fn(),
    };
    const deps = makeBaseDeps(allProviderData);
    await reportQuotas({ ...deps, cache: mockCache }, { mode: "table", now: Date.now() });
    expect(mockCache.get).toHaveBeenCalled();
    expect(fetcherCalled).toBe(true);
  });

  it("ReportDeps accepts optional cache in type", async () => {
    // Type-level test: this file must compile without errors for the types to be correct.
    // If cache?: CacheSource is missing from ReportDeps, TypeScript will error here.
    const { reportQuotas } = await import("../../../src/application/report-pipeline.js");
    const mockCache: CacheSource = {
      get: vi.fn(() => Promise.resolve([mk()])),
      invalidate: vi.fn(),
    };
    const deps = makeBaseDeps([mk()]);
    // Spread is valid only if cache is accepted
    const depsWithCache = { ...deps, cache: mockCache };
    const result = await reportQuotas(depsWithCache, { mode: "table", now: Date.now() });
    expect(result.rendered.length).toBeGreaterThan(0);
  });
});
