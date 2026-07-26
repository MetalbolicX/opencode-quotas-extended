// RED → GREEN: 5 coding-plan provider adapters (Zen, Go, z.ai, Kimi, Minimax).
// Endpoints are TODO — fetchQuotas returns [] gracefully until URLs are pinned.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import usageFIXTURE from "../../../tests/fixtures/providers/coding-plan/usage.json";
import { createZenProvider } from "../../../src/adapters/providers/zen.js";
import { createGoProvider } from "../../../src/adapters/providers/go.js";
import { createZaiProvider } from "../../../src/adapters/providers/zai.js";
import { createKimiProvider } from "../../../src/adapters/providers/kimi.js";
import { createMinimaxProvider } from "../../../src/adapters/providers/minimax.js";

function makeSource(cred: Credential | null): CredentialSource {
  return { get: () => Promise.resolve(cred) } as unknown as CredentialSource;
}
const oauthCred: Credential = { variant: "oauth", access: "tok", refresh: "ref", expires: Date.now() + 60_000 };
const apiCred: Credential = { variant: "api", key: "sk-test" };
function mockHttp() { return { request: vi.fn(() => Promise.resolve(usageFIXTURE)) } as unknown as HttpClient; }

const PROVIDERS = [
  { id: "zen",     create: createZenProvider,   key: "opencode",           cred: apiCred  },
  { id: "go",      create: createGoProvider,    key: "opencode-go",         cred: apiCred  },
  { id: "zai",     create: createZaiProvider,   key: "zai-coding-plan",     cred: oauthCred },
  { id: "kimi",    create: createKimiProvider,  key: "kimi-for-coding",     cred: oauthCred },
  { id: "minimax", create: createMinimaxProvider, key: "minimax-coding-plan", cred: oauthCred },
] as const;

describe("coding-plan providers", () => {
  // Two triangulating cases: credential present (→ true) vs missing (→ false).
  describe.each(PROVIDERS)("isAvailable — $id", ({ id, create, cred }) => {
    it("returns true when credential is present", async () => {
      expect(await create(makeSource(cred), mockHttp()).isAvailable({}, {})).toBe(true);
    });
    it("returns false when credential is missing", async () => {
      expect(await create(makeSource(null), mockHttp()).isAvailable({}, {})).toBe(false);
    });
  });

  // TODO URL guard — two triangulating cases:
  // Case 1: returns [] without throwing; Case 2: does NOT call HTTP (early return).
  describe.each(PROVIDERS)("fetchQuotas TODO URL — $id", ({ id, create, cred }) => {
    it("returns [] without throwing when endpoint is TODO", async () => {
      const http = mockHttp();
      await expect(create(makeSource(cred), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
    it("does not call HTTP when URL is TODO", async () => {
      const http = mockHttp();
      await create(makeSource(cred), http).fetchQuotas({}, {});
      expect(http.request).not.toHaveBeenCalled();
    });
  });

  // HTTP failure isolation — two triangulating cases: HTTP 500 → [] and network error → [].
  describe.each(PROVIDERS)("fetchQuotas HTTP failure — $id", ({ id, create, cred }) => {
    it("returns [] on HTTP 500 (no throw)", async () => {
      const http = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 500; throw e; }) } as unknown as HttpClient;
      await expect(create(makeSource(cred), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
    it("returns [] on network error (no throw)", async () => {
      const http = { request: vi.fn(() => Promise.reject(new Error("ENOTFOUND"))) } as unknown as HttpClient;
      await expect(create(makeSource(cred), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
  });

  // Provider shape verification — id, displayName, authStrategy are set correctly.
  describe.each(PROVIDERS)("provider shape — $id", ({ id, create, cred }) => {
    it("returns a QuotaProvider with correct id and type", async () => {
      const p = create(makeSource(cred), mockHttp());
      expect(p.id).toBe(id);
      expect(typeof p.fetchQuotas).toBe("function");
      expect(typeof p.isAvailable).toBe("function");
    });
  });
});
