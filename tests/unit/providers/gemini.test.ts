// Gemini Antigravity quota adapter — strict TDD unit tests.
// Antigravity: OAuth2 refresh + fetchAvailableModels quota endpoint.
// All HTTP is mocked; credential files are mocked via vi.spyOn on node:fs.
// RED first: tests written to fail → GREEN: minimal implementation → REFACTOR: good-comments.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import antigravityModelsFIXTURE from "../../../tests/fixtures/providers/gemini/antigravity-models.json";
import oauthTokenFIXTURE from "../../../tests/fixtures/providers/gemini/oauth-token-response.json";
import { createGeminiProvider } from "../../../src/adapters/providers/gemini.js";

// ── Test helpers ─────────────────────────────────────────────────────────────────

function makeSource(getFn: () => Promise<Credential | null> = () => Promise.resolve(null)): CredentialSource {
  return { get: getFn } as unknown as CredentialSource;
}

const oauthCred: Credential = { variant: "oauth", access: "old-token", refresh: "test-refresh", expires: Date.now() + 3600_000 };

// ── File system mock state ───────────────────────────────────────────────────────

interface MockFile {
  content: string | null;
}

const mockFiles: Record<string, MockFile> = {};

function mockFs(files: Record<string, string | null>) {
  for (const [path, content] of Object.entries(files)) {
    mockFiles[path] = { content };
  }
}

function clearMockFs() {
  for (const key of Object.keys(mockFiles)) {
    delete mockFiles[key];
  }
}

// Mock the node:fs module using vi.mock
vi.mock("node:fs", () => {
  const existsSync = vi.fn((path: string) => {
    return Object.keys(mockFiles).some(f => String(path).endsWith(f));
  });
  const readFileSync = vi.fn((path: string) => {
    const p = String(path);
    for (const [file, { content }] of Object.entries(mockFiles)) {
      if (p.endsWith(file)) {
        if (content === null) {
          const err = new Error(`ENOENT: ${file}`);
          (err as NodeJS.ErrnoException).code = "ENOENT";
          throw err;
        }
        return content;
      }
    }
    const err = new Error(`ENOENT: ${path}`);
    (err as NodeJS.ErrnoException).code = "ENOENT";
    throw err;
  });
  return { existsSync, readFileSync };
});

// ── Test scenarios ───────────────────────────────────────────────────────────────

describe("gemini Antigravity quota adapter", () => {

  beforeEach(() => {
    clearMockFs();
    vi.clearAllMocks();
  });

  afterEach(() => {
    clearMockFs();
  });

  // ── Scenario 1: OAuth refresh exchanges refresh_token for access_token ─────────
  describe("OAuth refresh", () => {
    it("POSTs to oauth2.googleapis.com/token with form-encoded body", async () => {
      let capturedTokenReq: unknown;
      let callCount = 0;
      const http = {
        request: vi.fn((r: unknown) => {
          callCount++;
          // Capture only the OAuth token call (first call)
          if (callCount === 1) {
            capturedTokenReq = r;
          }
          const req = r as { url?: string };
          return Promise.resolve(req.url?.includes("oauth") ? oauthTokenFIXTURE : antigravityModelsFIXTURE);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      await p.fetchQuotas();

      const req = capturedTokenReq as { url?: string; method?: string; headers?: Record<string, string>; body?: string };
      expect(req.url).toBe("https://oauth2.googleapis.com/token");
      expect(req.method).toBe("POST");
      expect(req.headers?.["Content-Type"]).toBe("application/x-www-form-urlencoded");
      expect(req.body).toContain("grant_type=refresh_token");
      expect(req.body).toContain("client_id=client-id");
      expect(req.body).toContain("client_secret=client-secret");
    });

    it("uses refreshed access_token in subsequent fetchAvailableModels call", async () => {
      const refreshedToken = "refreshed-access-token-****";
      const tokenResponse = { ...oauthTokenFIXTURE, access_token: refreshedToken };
      let capturedQuotaReq: unknown;

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(tokenResponse);
          capturedQuotaReq = r;
          return Promise.resolve(antigravityModelsFIXTURE);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      await p.fetchQuotas();

      const req = capturedQuotaReq as { headers?: Record<string, string> };
      expect(req.headers?.["Authorization"]).toBe(`Bearer ${refreshedToken}`);
    });
  });

  // ── Scenario 2: fetchAvailableModels POST with Bearer + project body ──────────
  describe("fetchAvailableModels request shape", () => {
    it("POSTs to cloudcode-pa.googleapis.com with project body", async () => {
      let capturedQuotaReq: unknown;

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          capturedQuotaReq = r;
          return Promise.resolve(antigravityModelsFIXTURE);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "my-test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      await p.fetchQuotas();

      const req = capturedQuotaReq as { url?: string; method?: string; headers?: Record<string, string>; body?: unknown };
      expect(req.url).toBe("https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels");
      expect(req.method).toBe("POST");
      expect(req.headers?.["Authorization"]).toBe("Bearer ****");
      expect(req.body).toEqual({ project: "my-test-project" });
    });
  });

  // ── Scenario 3: Single account, 4 models with quotaInfo → 4 QuotaData rows ────
  describe("QuotaData mapping — single account", () => {
    it("returns 3 QuotaData rows for 3 tracked models with quotaInfo", async () => {
      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve(antigravityModelsFIXTURE);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      // 3 tracked models: gemini-3-pro-high (0.72), gemini-3-pro-low (0.85), gemini-3-flash (0.95)
      // gemini-3-pro-image has quotaInfo=null → skipped
      // claude-opus-4-5-thinking is not a tracked model → skipped
      expect(quotas.length).toBe(3);

      // Verify structure
      for (const q of quotas) {
        expect(q.id).toMatch(/^gemini-/);
        expect(q.providerName).toBe("Google Gemini (Antigravity)");
        expect(q.limit).toBeNull(); // cap unknown
        expect(q.unit).toBe("fraction");
        expect(q.window).toBe("rolling");
        expect(q.predictedReset).toBeNull();
        expect(q.reset).toBeInstanceOf(Date);
        expect(q.info).toMatch(/\% remaining until/);
      }

      // Verify specific mappings
      const proHigh = quotas.find(q => q.id.includes("pro-high"));
      expect(proHigh?.info).toContain("gemini-3-pro-high");
      expect(proHigh?.info).toContain("72% remaining");

      const flash = quotas.find(q => q.id.includes("flash"));
      expect(flash?.info).toContain("gemini-3-flash");
      expect(flash?.info).toContain("95% remaining");
    });
  });

  // ── Scenario 4: Model with quotaInfo=null/partial → skip, no throw ────────────
  describe("Defensive parse — missing quotaInfo", () => {
    it("skips models with null quotaInfo without throwing", async () => {
      const fixture = {
        models: {
          "gemini-3-pro-image": { quotaInfo: null },
        },
      };

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve(fixture);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      await expect(p.fetchQuotas()).resolves.toEqual([]);
    });

    it("skips models with undefined quotaInfo without throwing", async () => {
      const fixture = {
        models: {
          "gemini-3-pro-high": { quotaInfo: { remainingFraction: 0.5 } },
          "gemini-3-flash": {},
        },
      };

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve(fixture);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();
      expect(quotas.length).toBe(1); // only gemini-3-pro-high
    });
  });

  // ── Scenario 5: Missing credential files → isAvailable returns false ───────────
  describe("isAvailable — credential presence", () => {
    it("returns false when no credential files exist", async () => {
      mockFs({}); // no files exist

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(null)), http);

      expect(await p.isAvailable()).toBe(false);
    });

    it("returns false when oauth source has no credential", async () => {
      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(null)), http);

      expect(await p.isAvailable()).toBe(false);
    });

    it("returns true when antigravity-accounts.json is present and oauth credential exists", async () => {
      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);

      expect(await p.isAvailable()).toBe(true);
    });
  });

  // ── Scenario 6: Multiple accounts via Promise.all — per-account error isolation
  describe("Multi-account error isolation", () => {
    it("returns rows from account 1 when account 2 throws", async () => {
      let callCount = 0;

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          callCount++;
          if (req.url?.includes("oauth")) {
            // Account 1 OAuth success, Account 2 OAuth throws
            if (callCount <= 2) return Promise.resolve(oauthTokenFIXTURE);
            throw new Error("OAuth error");
          }
          // Account 1 quota success
          if (callCount === 3) {
            return Promise.resolve({
              models: {
                "gemini-3-pro-high": { quotaInfo: { remainingFraction: 0.5, resetTime: "2026-07-27T00:00:00Z" } },
              },
            });
          }
          // Account 2 quota never called due to OAuth failure
          throw new Error("Should not be called");
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([
          {
            email: "account1@example.com",
            refreshToken: "refresh-1",
            clientId: "client-id-1",
            oauthSecret: "client-secret-1",
            projectId: "project-1",
          },
          {
            email: "account2@example.com",
            refreshToken: "refresh-2",
            clientId: "client-id-2",
            oauthSecret: "client-secret-2",
            projectId: "project-2",
          },
        ]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      // Should get account 1's rows despite account 2's failure
      expect(quotas.length).toBe(1);
      expect(quotas[0].id).toContain("gemini-3-pro-high");
    });

    it("queries all accounts concurrently via Promise.all", async () => {
      let callCount = 0;

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          callCount++;
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          // Return different model based on call order
          if (callCount === 3) {
            return Promise.resolve({
              models: {
                "gemini-3-flash": { quotaInfo: { remainingFraction: 0.9, resetTime: "2026-07-27T00:00:00Z" } },
              },
            });
          }
          return Promise.resolve({
            models: {
              "gemini-3-pro-high": { quotaInfo: { remainingFraction: 0.6, resetTime: "2026-07-27T00:00:00Z" } },
            },
          });
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([
          { email: "a@1.com", refreshToken: "r1", clientId: "c1", oauthSecret: "s1", projectId: "p1" },
          { email: "a@2.com", refreshToken: "r2", clientId: "c2", oauthSecret: "s2", projectId: "p2" },
        ]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      expect(quotas.length).toBe(2);
    });
  });

  // ── Scenario 7: Non-tracked models → skipped silently ────────────────────────
  describe("Non-tracked models", () => {
    it("skips models not in the tracked set", async () => {
      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve({
            models: {
              "gemini-3-pro-high": { quotaInfo: { remainingFraction: 0.5, resetTime: "2026-07-27T00:00:00Z" } },
              "unknown-model-x": { quotaInfo: { remainingFraction: 0.3, resetTime: "2026-07-27T00:00:00Z" } },
              "claude-opus-4-5-thinking": { quotaInfo: { remainingFraction: 0.4, resetTime: "2026-07-27T00:00:00Z" } },
            },
          });
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      // Only gemini-3-pro-high is tracked; others skipped
      expect(quotas.length).toBe(1);
      expect(quotas[0].id).toContain("gemini-3-pro-high");
    });
  });

  // ── Scenario 8: resetTime missing → reset=null, no throw ────────────────────
  describe("Missing resetTime", () => {
    it("sets reset=null when resetTime is absent", async () => {
      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve({
            models: {
              "gemini-3-flash": { quotaInfo: { remainingFraction: 0.75 } },
            },
          });
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      expect(quotas.length).toBe(1);
      expect(quotas[0].reset).toBeNull();
      expect(quotas[0].info).toContain("gemini-3-flash");
    });
  });

  // ── Scenario 9: Defensive parse — malformed models object ───────────────────
  describe("Defensive parse — malformed response", () => {
    it.each([
      { label: "null", value: null },
      { label: "undefined", value: undefined },
      { label: "models null", value: { models: null } },
      { label: "models string", value: { models: "not an object" } },
      { label: "model value not object", value: { models: { "gemini-3-pro-high": "not an object" } } },
      { label: "empty object", value: {} },
    ])("skips $label without throwing", async ({ value }) => {
      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve(value);
        }),
      } as unknown as HttpClient;

      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      await expect(p.fetchQuotas()).resolves.toEqual([]);
    });
  });

  // ── Scenario 10: isAvailable returns true when antigravity-accounts.json present
  describe("isAvailable — credential file detection", () => {
    it("returns true when antigravity-accounts.json exists with valid entry", async () => {
      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);

      expect(await p.isAvailable()).toBe(true);
    });

    it("returns true when auth.json.gemini fallback exists", async () => {
      mockFs({
        "auth.json.gemini": JSON.stringify({
          refresh: "fallback-refresh",
          projectId: "fallback-project",
          clientId: "fallback-client-id",
          oauthSecret: "fallback-client-secret",
        }),
      });

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);

      expect(await p.isAvailable()).toBe(true);
    });

    it("skips entries with missing required fields", async () => {
      mockFs({
        "antigravity-accounts.json": JSON.stringify([
          { email: "valid@example.com", refreshToken: "valid", clientId: "cid", oauthSecret: "cs", projectId: "pid" },
          { email: "incomplete@example.com" }, // missing refreshToken, clientId, etc.
        ]),
      });

      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve({
            models: {
              "gemini-3-pro-high": { quotaInfo: { remainingFraction: 0.5, resetTime: "2026-07-27T00:00:00Z" } },
            },
          });
        }),
      } as unknown as HttpClient;

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      // Should get 1 row from the valid account
      expect(quotas.length).toBe(1);
    });
  });

  // ── fetchQuotas returns [] when no accounts available ─────────────────────────
  describe("fetchQuotas — no available accounts", () => {
    it("returns [] when no credential files exist", async () => {
      mockFs({});

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(null)), http);

      await expect(p.fetchQuotas()).resolves.toEqual([]);
      expect(http.request).not.toHaveBeenCalled();
    });

    it("returns [] when oauth credential is missing", async () => {
      mockFs({
        "antigravity-accounts.json": JSON.stringify([{
          email: "test@example.com",
          refreshToken: "test-refresh",
          clientId: "client-id",
          oauthSecret: "client-secret",
          projectId: "test-project",
        }]),
      });

      const http = { request: vi.fn() } as unknown as HttpClient;
      const p = createGeminiProvider(makeSource(() => Promise.resolve(null)), http);

      await expect(p.fetchQuotas()).resolves.toEqual([]);
      expect(http.request).not.toHaveBeenCalled();
    });
  });

  // ── Fallback to auth.json.gemini ─────────────────────────────────────────────
  describe("auth.json.gemini fallback", () => {
    it("uses auth.json.gemini when antigravity-accounts.json is absent", async () => {
      const http = {
        request: vi.fn((r: unknown) => {
          const req = r as { url?: string };
          if (req.url?.includes("oauth")) return Promise.resolve(oauthTokenFIXTURE);
          return Promise.resolve(antigravityModelsFIXTURE);
        }),
      } as unknown as HttpClient;

      mockFs({
        "auth.json.gemini": JSON.stringify({
          refresh: "fallback-refresh",
          projectId: "fallback-project",
          clientId: "fallback-client-id",
          oauthSecret: "fallback-client-secret",
        }),
      });

      const p = createGeminiProvider(makeSource(() => Promise.resolve(oauthCred)), http);
      const quotas = await p.fetchQuotas();

      expect(quotas.length).toBeGreaterThan(0);
    });
  });
});
