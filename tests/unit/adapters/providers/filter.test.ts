// WU-3 RED: filterAvailableProviders is imported from shared adapter.
// REQ-LIST-2,3: unavailable providers excluded AND fetchQuotas never called.
// D-3: filter extracted from plugin/index.ts to src/adapters/providers/filter.ts.
import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import type { QuotaProvider } from "../../../../legacy/ports/provider.js";

// This import proves the filter is in the shared adapter (not duplicated inline).
// RED: this import fails until filter.ts is created in GREEN.
import { filterAvailableProviders } from "../../../../legacy/adapters/providers/filter.js";

// ── stdout/stderr capture ────────────────────────────────────────────────────

let stdout = "", stderr = "";
beforeEach(() => {
  stdout = ""; stderr = "";
  vi.spyOn(process.stdout, "write").mockImplementation((c: string) => (stdout += String(c), true));
  vi.spyOn(process.stderr, "write").mockImplementation((c: string) => (stderr += String(c), true));
});
afterEach(() => { vi.restoreAllMocks(); });

// ── Mock data ───────────────────────────────────────────────────────────────

// Track fetchQuotas calls
let unavailableFetchCalls = 0;
const unavailableFetch = vi.fn(() => { unavailableFetchCalls++; return Promise.resolve([]); });
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

// ── Tests ───────────────────────────────────────────────────────────────────

describe("filterAvailableProviders (from shared adapter)", () => {
  beforeEach(() => { unavailableFetchCalls = 0; });

  it("excludes unavailable providers and never calls their fetchQuotas", async () => {
    const available = await filterAvailableProviders(mockProviders);
    expect(available.map((p) => p.id)).toEqual(["available"]);
    expect(unavailableFetchCalls).toBe(0);
  });

  it("preserves registry ordering", async () => {
    const ordered = [
      { id: "a", displayName: "A", category: "api-spend", authStrategy: "api" as const, isAvailable: () => Promise.resolve(true), fetchQuotas: vi.fn() },
      { id: "b", displayName: "B", category: "api-spend", authStrategy: "env" as const, isAvailable: () => Promise.resolve(false), fetchQuotas: vi.fn() },
      { id: "c", displayName: "C", category: "api-spend", authStrategy: "api" as const, isAvailable: () => Promise.resolve(true), fetchQuotas: vi.fn() },
    ];
    const available = await filterAvailableProviders(ordered as QuotaProvider[]);
    expect(available.map((p) => p.id)).toEqual(["a", "c"]);
  });

  it("isolates one provider's isAvailable failure", async () => {
    const providers: QuotaProvider[] = [
      { id: "good", displayName: "Good", category: "api-spend", authStrategy: "api" as const, isAvailable: () => Promise.resolve(true), fetchQuotas: vi.fn() },
      { id: "throws", displayName: "Throws", category: "api-spend", authStrategy: "env" as const, isAvailable: () => { throw new Error("boom"); }, fetchQuotas: vi.fn() },
    ];
    const available = await filterAvailableProviders(providers);
    expect(available.map((p) => p.id)).toEqual(["good"]);
  });
});
