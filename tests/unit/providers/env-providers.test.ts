// RED → GREEN: Anthropic + Gemini env providers.
// All HTTP is mocked; endpoints are TODO — guarded to return [] until URLs are pinned.
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import { createAnthropicProvider } from "../../../src/adapters/providers/anthropic.js";
import { createGeminiProvider } from "../../../src/adapters/providers/gemini.js";
import usageFIXTURE from "../../../tests/fixtures/providers/env/usage.json";

function makeSource(getFn: () => Promise<Credential | null>): CredentialSource {
  return { get: getFn } as unknown as CredentialSource;
}

const apiKeyCred: Credential = { variant: "api", key: "sk-ant-..." };

const PROVIDERS = [
  { id: "anthropic", create: createAnthropicProvider },
  { id: "gemini",    create: createGeminiProvider    },
] as const;

function mockHttp(res: unknown = usageFIXTURE) {
  return { request: vi.fn(() => Promise.resolve(res)) } as unknown as HttpClient;
}

describe("env providers", () => {

  // ── isAvailable ───────────────────────────────────────────────────────────
  describe.each(PROVIDERS)("isAvailable — $id", ({ id, create }) => {
    it("returns true when env key is present", async () => {
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      expect(await create(src, mockHttp()).isAvailable({}, {})).toBe(true);
    });
    it("returns false when credential is missing", async () => {
      const src = makeSource(() => Promise.resolve(null));
      expect(await create(src, mockHttp()).isAvailable({}, {})).toBe(false);
    });
  });

  // ── TODO URL guard ────────────────────────────────────────────────────────
  describe.each(PROVIDERS)("fetchQuotas TODO URL — $id", ({ id, create }) => {
    it("returns [] without throwing when endpoint is TODO", async () => {
      const http = mockHttp();
      await expect(create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
    it("does not call HTTP when URL is TODO", async () => {
      const http = mockHttp();
      await create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {});
      expect(http.request).not.toHaveBeenCalled();
    });
  });

  // ── HTTP failure → [] ─────────────────────────────────────────────────────
  describe.each(PROVIDERS)("fetchQuotas HTTP failure — $id", ({ id, create }) => {
    it("returns [] on HTTP 500 (no throw)", async () => {
      const http = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 500; throw e; }) } as unknown as HttpClient;
      await expect(create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
    it("returns [] on network error (no throw)", async () => {
      const http = { request: vi.fn(() => Promise.reject(new Error("ENOTFOUND"))) } as unknown as HttpClient;
      await expect(create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
  });

  // ── Provider shape ────────────────────────────────────────────────────────
  describe.each(PROVIDERS)("provider shape — $id", ({ id, create }) => {
    it("returns a QuotaProvider with correct id and type", async () => {
      const p = create(makeSource(() => Promise.resolve(apiKeyCred)), mockHttp());
      expect(p.id).toBe(id);
      expect(typeof p.fetchQuotas).toBe("function");
      expect(typeof p.isAvailable).toBe("function");
    });
  });
});
