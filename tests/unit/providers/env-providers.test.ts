// RED → GREEN: Anthropic + Gemini env providers.
// All HTTP is mocked; endpoints are TODO — guarded to return [] until URLs are pinned.
// NOTE: Anthropic TODO replaced with real implementation. isAvailable now validates
// orgId resolution; fetchQuotas throws if orgId missing when config is provided.
// For backward compatibility with direct fetchQuotas calls without factory config,
// returns [] (not throw) when effectiveConfig is absent.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../legacy/ports/credentials.js";
import type { HttpClient } from "../../../legacy/ports/http.js";
import type { QuotasConfig } from "../../../legacy/adapters/infra/config-loader.js";
import { createAnthropicProvider } from "../../../legacy/adapters/providers/anthropic.js";
import { createGeminiProvider } from "../../../legacy/adapters/providers/gemini.js";
import usageFIXTURE from "../../../tests/fixtures/providers/env/usage.json";

function makeSource(getFn: () => Promise<Credential | null>): CredentialSource {
  return { get: getFn } as unknown as CredentialSource;
}

const apiKeyCred: Credential = { variant: "api", key: "sk-ant-..." };

// Minimal config with orgId for anthropic tests
const anthropicConfig: QuotasConfig = {
  displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24,
  pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5,
  showUnaggregated: false, show: true, anthropic: { orgId: "org_test" },
};
const emptyAuth = {};

const PROVIDERS_ANTHROPIC = [
  { id: "anthropic", create: createAnthropicProvider },
] as const;

const PROVIDERS_GEMINI = [
  { id: "gemini", create: createGeminiProvider },
] as const;

function mockHttp(res: unknown = usageFIXTURE) {
  return { request: vi.fn(() => Promise.resolve(res)) } as unknown as HttpClient;
}

describe("env providers", () => {

  // ── isAvailable — Anthropic (real implementation) ────────────────────────────
  describe.each(PROVIDERS_ANTHROPIC)("isAvailable — $id (orgId-gated)", ({ create }) => {
    it("returns true when credential + orgId present", async () => {
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      const p = create(src, mockHttp(), anthropicConfig, emptyAuth, {});
      expect(await (p as any).isAvailable()).toBe(true);
    });
    it("returns false when credential is missing", async () => {
      const src = makeSource(() => Promise.resolve(null));
      const p = create(src, mockHttp(), anthropicConfig, emptyAuth, {});
      expect(await (p as any).isAvailable()).toBe(false);
    });
    it("returns false when credential present but orgId missing", async () => {
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      const noOrgIdConfig: QuotasConfig = { ...anthropicConfig, anthropic: undefined as unknown as { orgId: string } };
      const p = create(src, mockHttp(), noOrgIdConfig as QuotasConfig, emptyAuth, {});
      expect(await (p as any).isAvailable()).toBe(false);
    });
  });

  // ── isAvailable — Gemini (Antigravity) ─────────────────────────────────────
  // isAvailable returns true when antigravity-accounts.json exists AND oauth credential present.
  // Tests for the OLD placeholder (env key) behavior removed — replaced by Antigravity.
  describe.each(PROVIDERS_GEMINI)("isAvailable — $id (Antigravity)", ({ create }) => {
    // No mock fs setup — antigravity-accounts.json not present
    it("returns false when no credential files exist", async () => {
      const src = makeSource(() => Promise.resolve(null));
      expect(await create(src, mockHttp()).isAvailable({}, {})).toBe(false);
    });
    // credSrc returns null — no oauth credential even though file might exist
    it("returns false when oauth credential is missing (file may exist)", async () => {
      // Note: Without mock fs, loadAntigravityAccounts returns null
      const src = makeSource(() => Promise.resolve(null));
      expect(await create(src, mockHttp()).isAvailable({}, {})).toBe(false);
    });
  });

  // ── fetchQuotas — Anthropic with valid config ───────────────────────────────
  describe.each(PROVIDERS_ANTHROPIC)("fetchQuotas — $id (config provided)", ({ create }) => {
    it("returns QuotaData[] on HTTP 200", async () => {
      const http = mockHttp(usageFIXTURE);
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      const p = create(src, http, anthropicConfig, emptyAuth, {});
      await expect((p as any).fetchQuotas()).resolves.not.toThrow();
    });
    it("throws redacted error on 401/403", async () => {
      const http = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 403; throw e; }) } as unknown as HttpClient;
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      const p = create(src, http, anthropicConfig, emptyAuth, {});
      await expect((p as any).fetchQuotas()).rejects.toThrow(/admin|permission/i);
    });
    it("throws on other HTTP errors", async () => {
      const http = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 500; throw e; }) } as unknown as HttpClient;
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      const p = create(src, http, anthropicConfig, emptyAuth, {});
      await expect((p as any).fetchQuotas()).rejects.toThrow();
    });
  });

  // ── fetchQuotas — Anthropic without factory config (backward compat) ─────────
  describe("fetchQuotas — anthropic (no factory config, direct call)", () => {
    // When fetchQuotas is called without factory config, effectiveConfig is undefined.
    // This should return [] (not throw) for backward compatibility with direct calls.
    it("returns [] when no config (no throw)", async () => {
      const http = mockHttp();
      const src = makeSource(() => Promise.resolve(apiKeyCred));
      const p = createAnthropicProvider(src, http);
      await expect((p as any).fetchQuotas()).resolves.toEqual([]);
    });
  });

  // ── fetchQuotas — Gemini (placeholder, returns []) ───────────────────────────
  describe.each(PROVIDERS_GEMINI)("fetchQuotas — $id", ({ create }) => {
    it("returns [] without throwing when endpoint is TODO", async () => {
      const http = mockHttp();
      await expect(create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
    it("does not call HTTP when URL is TODO", async () => {
      const http = mockHttp();
      await create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {});
      expect(http.request).not.toHaveBeenCalled();
    });
    it("returns [] on HTTP 500 (no throw)", async () => {
      const http = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 500; throw e; }) } as unknown as HttpClient;
      await expect(create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
    it("returns [] on network error (no throw)", async () => {
      const http = { request: vi.fn(() => Promise.reject(new Error("ENOTFOUND"))) } as unknown as HttpClient;
      await expect(create(makeSource(() => Promise.resolve(apiKeyCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
    });
  });

  // ── Provider shape ─────────────────────────────────────────────────────────
  describe.each([...PROVIDERS_ANTHROPIC, ...PROVIDERS_GEMINI])("provider shape — $id", ({ id, create }) => {
    it("returns a QuotaProvider with correct id and type", async () => {
      const p = create(makeSource(() => Promise.resolve(apiKeyCred)), mockHttp());
      expect(p.id).toBe(id);
      expect(typeof (p as any).fetchQuotas).toBe("function");
      expect(typeof (p as any).isAvailable).toBe("function");
    });
  });
});
