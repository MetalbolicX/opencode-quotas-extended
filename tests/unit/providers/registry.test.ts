// RED → GREEN: provider registry + buildDefaultRegistry (all 8 providers).
import { describe, it, expect, vi } from "vitest";
import type { CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import type { QuotaProvider } from "../../../src/ports/provider.js";
import { createProviderRegistry, buildDefaultRegistry } from "../../../src/adapters/providers/registry.js";

const dummy = (id: string): QuotaProvider => ({
  id, displayName: id, category: "api-spend", authStrategy: "api",
  isAvailable: async () => true, fetchQuotas: async () => [],
});

const fakeCredSrc: CredentialSource = { get: async () => null } as unknown as CredentialSource;
const fakeHttp: HttpClient = { request: vi.fn() } as unknown as HttpClient;

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

describe("buildDefaultRegistry", () => {
  it("returns a registry with all 8 providers registered", () => {
    const r = buildDefaultRegistry(fakeCredSrc, fakeHttp);
    const ids = r.list().map((p) => p.id).sort();
    expect(ids).toEqual([
      "anthropic",
      "gemini",
      "go",
      "kimi",
      "minimax",
      "openai",
      "zai",
      "zen",
    ].sort());
  });

  it("each registered provider is a QuotaProvider shape", () => {
    const r = buildDefaultRegistry(fakeCredSrc, fakeHttp);
    for (const p of r.list()) {
      expect(typeof p.id).toBe("string");
      expect(typeof p.displayName).toBe("string");
      expect(typeof p.fetchQuotas).toBe("function");
      expect(typeof p.isAvailable).toBe("function");
    }
  });
});
