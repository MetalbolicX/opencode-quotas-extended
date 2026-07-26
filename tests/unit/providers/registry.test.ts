// RED → GREEN: provider registry.
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { QuotaProvider } from "../../../src/ports/provider.js";
import type { FetchContext } from "../../../src/ports/http.js";
import { createProviderRegistry } from "../../../src/adapters/providers/registry.js";

const dummyProvider: QuotaProvider = {
  id: "test",
  displayName: "Test",
  category: "api-spend",
  authStrategy: "api",
  isAvailable: async (_cred, _ctx) => true,
  fetchQuotas: async (_cred, _ctx) => [],
};

const openaiProvider: QuotaProvider = {
  id: "openai",
  displayName: "OpenAI",
  category: "subscription",
  authStrategy: "oauth",
  isAvailable: async (_cred, _ctx) => true,
  fetchQuotas: async (_cred, _ctx) => [],
};

describe("provider-registry", () => {
  let registry: ReturnType<typeof createProviderRegistry>;

  beforeEach(() => {
    registry = createProviderRegistry();
  });

  it("returns undefined for unregistered provider", () => {
    expect(registry.get("openai")).toBeUndefined();
  });

  it("returns registered provider by id", () => {
    registry.register(openaiProvider);
    expect(registry.get("openai")).toBe(openaiProvider);
  });

  it("list returns all registered providers", () => {
    registry.register(dummyProvider);
    registry.register(openaiProvider);
    const list = registry.list();
    expect(list).toHaveLength(2);
    expect(list.map((p) => p.id)).toContain("test");
    expect(list.map((p) => p.id)).toContain("openai");
  });
});
