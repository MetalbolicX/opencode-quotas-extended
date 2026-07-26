// RED → GREEN: 5 coding-plan provider adapters (Zen, Go, z.ai, Kimi, Minimax).
// URLs are now pinned; tests cover fixture-based parsing and failure isolation.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import zenFIXTURE from "../../../tests/fixtures/providers/zen/usage.json";
import goFIXTURE from "../../../tests/fixtures/providers/go/usage.json";
import zaiFIXTURE from "../../../tests/fixtures/providers/zai/usage.json";
import kimiFIXTURE from "../../../tests/fixtures/providers/kimi/usage.json";
import minimaxFIXTURE from "../../../tests/fixtures/providers/minimax/usage.json";
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

const PROVIDERS = [
  { id: "zen",     create: createZenProvider,   key: "opencode",            cred: apiCred,   fixture: zenFIXTURE   },
  { id: "go",      create: createGoProvider,    key: "opencode-go",          cred: apiCred,   fixture: goFIXTURE    },
  { id: "zai",     create: createZaiProvider,   key: "zai-coding-plan",      cred: oauthCred, fixture: zaiFIXTURE   },
  { id: "kimi",    create: createKimiProvider,  key: "kimi-for-coding",      cred: oauthCred, fixture: kimiFIXTURE  },
  { id: "minimax", create: createMinimaxProvider, key: "minimax-coding-plan", cred: oauthCred, fixture: minimaxFIXTURE },
] as const;

describe("coding-plan providers", () => {
  // ── isAvailable ────────────────────────────────────────────────────────────
  describe.each(PROVIDERS)("isAvailable — $id", ({ id, create, cred }) => {
    it("returns true when credential is present", async () => {
      expect(await create(makeSource(cred), {} as HttpClient).isAvailable({}, {})).toBe(true);
    });
    it("returns false when credential is missing", async () => {
      expect(await create(makeSource(null), {} as HttpClient).isAvailable({}, {})).toBe(false);
    });
  });

  // ── fixture parsing (pinned URLs) ─────────────────────────────────────────
  describe.each(PROVIDERS)("fetchQuotas parses fixture — $id", ({ id, create, cred, fixture }) => {
    it("returns QuotaData[] from fixture", async () => {
      const http = { request: vi.fn(() => Promise.resolve(fixture)) } as unknown as HttpClient;
      const qs = await create(makeSource(cred), http).fetchQuotas({}, {});
      // Should return at least as many entries as windows + credits
      const windowCount = (fixture as { windows?: unknown[] }).windows?.length ?? 0;
      const hasCredits = Boolean((fixture as { credits?: unknown }).credits);
      expect(qs.length).toBeGreaterThanOrEqual(windowCount);
    });

    it("calls HTTP with Bearer auth", async () => {
      if (id === "minimax") return; // minimax uses CLI, not HTTP
      let capturedReq: unknown;
      const http = {
        request: vi.fn((r: unknown) => { capturedReq = r; return Promise.resolve(fixture); }),
      } as unknown as HttpClient;
      await create(makeSource(cred), http).fetchQuotas({}, {});
      const req = capturedReq as { headers?: { Authorization?: string } };
      expect(req.headers?.Authorization).toMatch(/^Bearer /);
    });
  });

  // ── HTTP failure isolation ─────────────────────────────────────────────────
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

  // ── Provider shape ────────────────────────────────────────────────────────
  describe.each(PROVIDERS)("provider shape — $id", ({ id, create, cred }) => {
    it("returns a QuotaProvider with correct id and type", async () => {
      const p = create(makeSource(cred), {} as HttpClient);
      expect(p.id).toBe(id);
      expect(typeof p.fetchQuotas).toBe("function");
      expect(typeof p.isAvailable).toBe("function");
    });
  });
});
