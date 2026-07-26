// RED → GREEN: provider registry.
import { describe, it, expect, vi } from "vitest";
import type { QuotaProvider } from "../../../src/ports/provider.js";
import { createProviderRegistry } from "../../../src/adapters/providers/registry.js";

const dummy = (id: string): QuotaProvider => ({ id, displayName: id, category: "api-spend", authStrategy: "api", isAvailable: async () => true, fetchQuotas: async () => [] });

describe("provider-registry", () => {
  it("get returns undefined for unregistered", () => {
    expect(createProviderRegistry().get("x")).toBeUndefined();
  });

  it("get returns registered provider", () => {
    const r = createProviderRegistry(); r.register(dummy("a"));
    expect(r.get("a")?.id).toBe("a");
  });

  it("list returns all registered", () => {
    const r = createProviderRegistry(); r.register(dummy("a")); r.register(dummy("b"));
    expect(r.list().map((p) => p.id)).toEqual(["a", "b"]);
  });
});
