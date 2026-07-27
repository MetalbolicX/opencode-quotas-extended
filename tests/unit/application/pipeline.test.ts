// WU-6 RED: Pipeline — one provider failure does NOT fail others.
// Promise.allSettled means partial results are returned even when some providers throw.
import { describe, it, expect, vi } from "vitest";
import type { QuotaData } from "../../../src/domain/types.js";
import type { CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import type { Logger } from "../../../src/ports/logger.js";
import { reportQuotas } from "../../../src/application/report-pipeline.js";
import type { ReportResult } from "../../../src/application/report-pipeline.js";

const noopLogger: Logger = { debug() {}, info() {}, warn() {}, error() {} };

const baseConfig = {
  displayMode: "table" as const,
  disabled: [] as readonly string[],
  aggregatedGroups: {} as Readonly<Record<string, { strategy: string; members: readonly string[] }>>,
  historyMaxAgeHours: 24,
  predictionWindowMinutes: 60,
  predictionShortWindowMinutes: 5,
  showUnaggregated: true,
};

function makeSource(getFn: () => Promise<null>) {
  return { get: getFn } as unknown as CredentialSource;
}

// Minimal provider stub that always succeeds
function makeSuccessProvider(id: string, quotas: QuotaData[]) {
  return {
    id,
    displayName: id,
    category: "subscription" as const,
    authStrategy: "api" as const,
    isAvailable: () => Promise.resolve(true),
    fetchQuotas: () => Promise.resolve(quotas),
  };
}

// Provider stub that always throws
function makeFailingProvider(id: string, reason: string) {
  return {
    id,
    displayName: id,
    category: "subscription" as const,
    authStrategy: "api" as const,
    isAvailable: () => Promise.resolve(true),
    fetchQuotas: () => Promise.reject(new Error(reason)),
  };
}

// Mock history store
const mockHistory = {
  append: vi.fn(),
  getHistory: vi.fn(() => Promise.resolve([])),
  prune: vi.fn(),
  resetDetected: () => false,
};

describe("pipeline — partial-result flow (WU-6)", () => {
  it("one provider failure does NOT fail other providers; result includes data + errors", async () => {
    const registry = {
      list: () => [
        makeSuccessProvider("good-a", [
          { id: "good-a/daily", providerName: "Good A", used: 10, limit: 100, unit: "%", window: "daily", reset: null, predictedReset: null, info: "good" },
        ]),
        makeFailingProvider("bad-one", "connection refused"),
        makeSuccessProvider("good-b", [
          { id: "good-b/daily", providerName: "Good B", used: 20, limit: 100, unit: "%", window: "daily", reset: null, predictedReset: null, info: "good" },
        ]),
      ],
      get: (id: string) => {
        const all = [
          makeSuccessProvider("good-a", [
            { id: "good-a/daily", providerName: "Good A", used: 10, limit: 100, unit: "%", window: "daily", reset: null, predictedReset: null, info: "good" },
          ]),
          makeFailingProvider("bad-one", "connection refused"),
          makeSuccessProvider("good-b", [
            { id: "good-b/daily", providerName: "Good B", used: 20, limit: 100, unit: "%", window: "daily", reset: null, predictedReset: null, info: "good" },
          ]),
        ];
        return all.find((p) => p.id === id);
      },
    };

    const result: ReportResult = await reportQuotas(
      {
        credentialResolver: makeSource(() => Promise.resolve(null)),
        httpClient: {} as HttpClient,
        registry,
        historyStore: mockHistory,
        config: baseConfig,
        logger: noopLogger,
      },
      { mode: "table" },
    );

    // Two successful quotas should be present
    expect(result.rendered.length).toBeGreaterThan(0);

    // Error for the failing provider must be recorded (pipeline uses String(reason))
    expect(result.errors["bad-one"]).toMatch("connection refused");

    // Other providers must NOT appear in errors
    expect(result.errors["good-a"]).toBeUndefined();
    expect(result.errors["good-b"]).toBeUndefined();
  });

  it("pipeline returns errors{} when all providers succeed", async () => {
    const registry = {
      list: () => [
        makeSuccessProvider("good-a", [
          { id: "good-a/daily", providerName: "Good A", used: 10, limit: 100, unit: "%", window: "daily", reset: null, predictedReset: null, info: "good" },
        ]),
      ],
      get: (id: string) => registry.list().find((p) => p.id === id),
    };

    const result: ReportResult = await reportQuotas(
      {
        credentialResolver: makeSource(() => Promise.resolve(null)),
        httpClient: {} as HttpClient,
        registry,
        historyStore: mockHistory,
        config: baseConfig,
        logger: noopLogger,
      },
      { mode: "table" },
    );

    expect(result.errors).toEqual({});
  });
});
