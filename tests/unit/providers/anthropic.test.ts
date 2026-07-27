// RED → GREEN: Anthropic admin-usage parser.
// isAvailable gating + orgId resolution priority + defensive pagination + fail-fast auth errors.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import type { QuotasConfig } from "../../../src/adapters/infra/config-loader.js";
import { createAnthropicProvider } from "../../../src/adapters/providers/anthropic.js";
import usageFIXTURE from "../../../tests/fixtures/providers/anthropic/usage.json";
import page2FIXTURE from "../../../tests/fixtures/providers/anthropic/usage-page-2.json";
import page2TerminalFIXTURE from "../../../tests/fixtures/providers/anthropic/usage-page-2-terminal.json";

// ── helpers ───────────────────────────────────────────────────────────────────

function makeSource(cred: Credential | null): CredentialSource {
  return { get: vi.fn(() => Promise.resolve(cred)) } as unknown as CredentialSource;
}

const apiCred: Credential = { variant: "api", key: "sk-anthropic-test" };

const emptyAuth: Record<string, unknown> = {};
const emptyEnv: Record<string, string | undefined> = {};

const baseConfig: QuotasConfig = {
  displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24,
  pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5,
  showUnaggregated: false, show: true,
};

// ── isAvailable ────────────────────────────────────────────────────────────────

describe("anthropic isAvailable", () => {
  it("returns false when no credential", async () => {
    const provider = createAnthropicProvider(makeSource(null), { request: vi.fn() } as unknown as HttpClient);
    expect(await (provider as any).isAvailable()).toBe(false);
  });

  it("returns true when credential present (orgId from config)", async () => {
    const cfg: QuotasConfig = { ...baseConfig, anthropic: { orgId: "org_cfg" } };
    const provider = createAnthropicProvider(makeSource(apiCred), { request: vi.fn() } as unknown as HttpClient, cfg, emptyAuth, emptyEnv);
    expect(await (provider as any).isAvailable()).toBe(true);
  });

  it("returns true when credential present (orgId from auth.json)", async () => {
    const auth = { anthropic: { orgId: "org_auth" } };
    const provider = createAnthropicProvider(makeSource(apiCred), { request: vi.fn() } as unknown as HttpClient, baseConfig, auth, emptyEnv);
    expect(await (provider as any).isAvailable()).toBe(true);
  });

  it("returns true when credential present (orgId from env)", async () => {
    const env: Record<string, string | undefined> = { ANTHROPIC_ORG_ID: "org_env" };
    const provider = createAnthropicProvider(makeSource(apiCred), { request: vi.fn() } as unknown as HttpClient, baseConfig, emptyAuth, env);
    expect(await (provider as any).isAvailable()).toBe(true);
  });

  it("returns false when credential present but no orgId resolves", async () => {
    // isAvailable returns false (not throws) so the pipeline silently skips.
    const provider = createAnthropicProvider(makeSource(apiCred), { request: vi.fn() } as unknown as HttpClient, baseConfig, emptyAuth, emptyEnv);
    expect(await (provider as any).isAvailable()).toBe(false);
  });
});

// ── fetchQuotas: orgId resolution priority ────────────────────────────────────

describe("anthropic fetchQuotas — orgId resolution", () => {
  it("orgId from config → 200 → QuotaData[] with strict window union", async () => {
    let capturedUrl: string | undefined;
    const http = {
      request: vi.fn((req: { url: string }) => { capturedUrl = req.url; return Promise.resolve(usageFIXTURE); }),
    } as unknown as HttpClient;
    const cfg: QuotasConfig = { ...baseConfig, anthropic: { orgId: "org_cfg" } };
    const provider = createAnthropicProvider(makeSource(apiCred), http, cfg, emptyAuth, emptyEnv);
    const qs = await (provider as any).fetchQuotas();
    expect(capturedUrl).toContain("/organizations/org_cfg/usage");
    expect(qs.length).toBeGreaterThan(0);
    for (const q of qs) {
      expect(["daily", "monthly", "rolling"]).toContain(q.window);
    }
  });

  it("orgId from auth.json fallback", async () => {
    let capturedUrl: string | undefined;
    const http = {
      request: vi.fn((req: { url: string }) => { capturedUrl = req.url; return Promise.resolve(usageFIXTURE); }),
    } as unknown as HttpClient;
    const auth = { anthropic: { orgId: "org_auth" } };
    const provider = createAnthropicProvider(makeSource(apiCred), http, baseConfig, auth, emptyEnv);
    const qs = await (provider as any).fetchQuotas();
    expect(capturedUrl).toContain("/organizations/org_auth/usage");
    expect(qs.length).toBeGreaterThan(0);
  });

  it("orgId from ANTHROPIC_ORG_ID env fallback", async () => {
    let capturedUrl: string | undefined;
    const http = {
      request: vi.fn((req: { url: string }) => { capturedUrl = req.url; return Promise.resolve(usageFIXTURE); }),
    } as unknown as HttpClient;
    const env: Record<string, string | undefined> = { ANTHROPIC_ORG_ID: "org_env" };
    const provider = createAnthropicProvider(makeSource(apiCred), http, baseConfig, emptyAuth, env);
    const qs = await (provider as any).fetchQuotas();
    expect(capturedUrl).toContain("/organizations/org_env/usage");
    expect(qs.length).toBeGreaterThan(0);
  });

  it("missing orgId → throws actionable error (no silent [])", async () => {
    const http = { request: vi.fn() } as unknown as HttpClient;
    const provider = createAnthropicProvider(makeSource(apiCred), http, baseConfig, emptyAuth, emptyEnv);
    await expect((provider as any).fetchQuotas()).rejects.toThrow(/org.*id|anthropic\.orgId|ANTHROPIC_ORG_ID/i);
  });
});

// ── fetchQuotas: auth failures ────────────────────────────────────────────────

describe("anthropic fetchQuotas — auth failures", () => {
  async function authFailure(status: number) {
    const http = {
      request: vi.fn(async () => {
        const e = new Error("forbidden");
        (e as Error & { status?: number }).status = status;
        throw e;
      }),
    } as unknown as HttpClient;
    const cfg: QuotasConfig = { ...baseConfig, anthropic: { orgId: "org_cfg" } };
    const provider = createAnthropicProvider(makeSource(apiCred), http, cfg, emptyAuth, emptyEnv);
    return (provider as any).fetchQuotas();
  }

  it("401 → throws redacted actionable error", async () => {
    await expect(authFailure(401)).rejects.toThrow(/admin|usage.*read|permission/i);
  });

  it("403 → throws redacted actionable error", async () => {
    await expect(authFailure(403)).rejects.toThrow(/admin|usage.*read|permission/i);
  });
});

// ── fetchQuotas: pagination ───────────────────────────────────────────────────

describe("anthropic fetchQuotas — pagination", () => {
  it("has_more multi-page → aggregates entries from both pages", async () => {
    const requests: string[] = [];
    const http = {
      request: vi.fn((req: { url: string }) => {
        requests.push(req.url);
        if (requests.length === 1) return Promise.resolve(page2FIXTURE);
        return Promise.resolve(page2TerminalFIXTURE);
      }),
    } as unknown as HttpClient;
    const cfg: QuotasConfig = { ...baseConfig, anthropic: { orgId: "org_cfg" } };
    const provider = createAnthropicProvider(makeSource(apiCred), http, cfg, emptyAuth, emptyEnv);
    const qs = await (provider as any).fetchQuotas();
    expect(qs).toHaveLength(2);
    expect(http.request).toHaveBeenCalledTimes(2);
  });

  it("has_more cap 20 → loop terminates at 20 pages", async () => {
    const infiniteFixture = {
      data: [{ usage: { input_tokens: 1, output_tokens: 0, total_tokens: 1 }, model: "claude-3-5-sonnet", workspace_id: "ws_****", time_bucket: "2026-07-26T00:00:00Z" }],
      has_more: true,
      next_page: "cursor_next",
    };
    const http = { request: vi.fn(() => Promise.resolve(infiniteFixture)) } as unknown as HttpClient;
    const cfg: QuotasConfig = { ...baseConfig, anthropic: { orgId: "org_cfg" } };
    const provider = createAnthropicProvider(makeSource(apiCred), http, cfg, emptyAuth, emptyEnv);
    await (provider as any).fetchQuotas();
    expect(http.request).toHaveBeenCalledTimes(20);
  });
});

// ── fetchQuotas: defensive parse ───────────────────────────────────────────────

describe("anthropic fetchQuotas — defensive parse", () => {
  it("unknown JSON shape → returns [] with warning (no throw)", async () => {
    const http = {
      request: vi.fn(() => Promise.resolve({ totally: "unexpected", shape: { nested: 123 } })),
    } as unknown as HttpClient;
    const cfg: QuotasConfig = { ...baseConfig, anthropic: { orgId: "org_cfg" } };
    const provider = createAnthropicProvider(makeSource(apiCred), http, cfg, emptyAuth, emptyEnv);
    await expect((provider as any).fetchQuotas()).resolves.toEqual([]);
  });
});
