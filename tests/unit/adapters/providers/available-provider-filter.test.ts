// RED: unavailable providers must not have fetchQuotas() called
// Regression: gemini (isAvailable=false) must not trigger fetchQuotas() → no warning logged.
import { describe, it, expect, vi } from "vitest";
import type { QuotaProvider } from "../../../../legacy/ports/provider.js";

const fakeQuota = (id: string) => ({
  id, providerName: id, used: 50, limit: 100, unit: "requests",
  reset: null, window: "daily" as const,
});

describe("available-provider filter", () => {
  it("fetchQuotas is NOT called for providers where isAvailable() returns false", async () => {
    const unavailableFetch = vi.fn().mockResolvedValue([fakeQuota("unavailable")]);
    const availableFetch = vi.fn().mockResolvedValue([fakeQuota("available")]);

    const unavailableProvider: QuotaProvider = {
      id: "unavailable",
      displayName: "Unavailable",
      category: "api-spend",
      authStrategy: "env",
      isAvailable: async () => false,
      fetchQuotas: unavailableFetch,
    };

    const availableProvider: QuotaProvider = {
      id: "available",
      displayName: "Available",
      category: "api-spend",
      authStrategy: "api",
      isAvailable: async () => true,
      fetchQuotas: availableFetch,
    };

    const registry = { list: () => [unavailableProvider, availableProvider] };

    // Import the helper under test
    const { filterAvailableProviders } = await import("../../../../legacy/adapters/providers/filter.js");

    const available = await filterAvailableProviders(registry.list());

    expect(available.map((p) => p.id)).toEqual(["available"]);
    expect(unavailableFetch).not.toHaveBeenCalled();
    // filterAvailableProviders is a pure filter — fetchQuotas is called by the
    // cache fetcher AFTER filtering, not by this helper itself.
  });

  it("preserves provider ordering (available providers stay in registry order)", async () => {
    const fetchA = vi.fn().mockResolvedValue([fakeQuota("a")]);
    const fetchB = vi.fn().mockResolvedValue([fakeQuota("b")]);
    const fetchC = vi.fn().mockResolvedValue([fakeQuota("c")]);

    const providers: QuotaProvider[] = [
      { id: "first-available", displayName: "A", category: "api-spend", authStrategy: "api", isAvailable: async () => true, fetchQuotas: fetchA },
      { id: "middle-unavailable", displayName: "B", category: "api-spend", authStrategy: "env", isAvailable: async () => false, fetchQuotas: fetchB },
      { id: "last-available", displayName: "C", category: "api-spend", authStrategy: "api", isAvailable: async () => true, fetchQuotas: fetchC },
    ];

    const registry = { list: () => providers };

    const { filterAvailableProviders } = await import("../../../../legacy/adapters/providers/filter.js");

    const available = await filterAvailableProviders(registry.list());

    expect(available.map((p) => p.id)).toEqual(["first-available", "last-available"]);
  });

  it("one provider's isAvailable() failure does not prevent other providers", async () => {
    const fetchA = vi.fn().mockResolvedValue([fakeQuota("a")]);
    const fetchB = vi.fn().mockResolvedValue([fakeQuota("b")]);

    const providers: QuotaProvider[] = [
      { id: "good-a", displayName: "A", category: "api-spend", authStrategy: "api", isAvailable: async () => true, fetchQuotas: fetchA },
      {
        id: "throws-b",
        displayName: "B",
        category: "api-spend",
        authStrategy: "env",
        isAvailable: async () => { throw new Error("isAvailable bombed"); },
        fetchQuotas: fetchB,
      },
    ];

    const registry = { list: () => providers };

    const { filterAvailableProviders } = await import("../../../../legacy/adapters/providers/filter.js");

    // Should not throw; "throws-b" is excluded but "good-a" is still included
    const available = await filterAvailableProviders(registry.list());

    expect(available.map((p) => p.id)).toEqual(["good-a"]);
    expect(fetchA).not.toHaveBeenCalled(); // only filtered, not fetched here
  });
});
