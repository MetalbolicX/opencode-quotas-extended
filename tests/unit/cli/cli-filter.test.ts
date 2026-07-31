// WU-3 RED: CLI filter integration test.
// REQ-LIST-2,3: unavailable providers are excluded AND fetchQuotas is never called.
// D-3: filterAvailableProviders extracted to src/adapters/providers/filter.ts.
import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import type { QuotaProvider } from "../../../legacy/ports/provider.js";

// ── stdout/stderr capture ────────────────────────────────────────────────────

let stdout = "", stderr = "";
beforeEach(() => {
  stdout = ""; stderr = "";
  vi.spyOn(process.stdout, "write").mockImplementation((c: string) => (stdout += String(c), true));
  vi.spyOn(process.stderr, "write").mockImplementation((c: string) => (stderr += String(c), true));
});
afterEach(() => { vi.restoreAllMocks(); });

// ── Mock data with spy fetchQuotas ──────────────────────────────────────────

// Track fetchQuotas calls across the registry mock
const fetchQuotasCalls = { unavailable: 0 };

const unavailableFetch = vi.fn(() => { fetchQuotasCalls.unavailable++; return Promise.resolve([]); });
const availableFetch = vi.fn().mockResolvedValue([]);

const mockProviders: QuotaProvider[] = [
  {
    id: "available",
    displayName: "Available Provider",
    category: "api-spend",
    authStrategy: "api",
    isAvailable: () => Promise.resolve(true),
    fetchQuotas: availableFetch,
  },
  {
    id: "unavailable",
    displayName: "Unavailable Provider",
    category: "api-spend",
    authStrategy: "env",
    isAvailable: () => Promise.resolve(false),
    fetchQuotas: unavailableFetch,
  },
];

const { mockBuildDefaultRegistry } = vi.hoisted(() => ({
  mockBuildDefaultRegistry: vi.fn(() => ({
    list: () => mockProviders,
    get: (id: string) => mockProviders.find((p) => p.id === id),
  })),
}));

vi.mock("../../../legacy/adapters/providers/registry.js", () => ({
  buildDefaultRegistry: mockBuildDefaultRegistry,
}));

vi.mock("../../../legacy/adapters/infra/config-loader.js", () => ({
  DEFAULTS: { displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } },
  loadConfig: vi.fn(() => ({ displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } })),
}));

vi.mock("../../../legacy/adapters/auth/credential-resolver.js", () => ({
  createCredentialResolver: vi.fn(() => ({ get: () => Promise.resolve(null) })),
}));

vi.mock("../../../legacy/adapters/infra/fetch-http.js", () => ({
  FetchHttpClient: vi.fn().mockImplementation(function () { this.request = vi.fn(); }),
}));

// ── Import after mocks ─────────────────────────────────────────────────────────

import { run } from "../../../legacy/cli/index.js";

describe("CLI --list filter integration", () => {
  it("SCENARIO: unavailable provider is absent from --list output and fetchQuotas is never called", async () => {
    const result = await run(["--list"]);
    expect(result.exitCode).toBe(0);
    // "unavailable" must NOT appear in the list output
    expect(result.stdout).not.toContain("unavailable");
    // Only "available" appears
    expect(result.stdout).toContain("available");
    // fetchQuotas must NEVER have been called on the unavailable provider
    expect(fetchQuotasCalls.unavailable).toBe(0);
  });
});
