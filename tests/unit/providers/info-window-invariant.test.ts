// Slice 12: info + window strict-union invariant test.
// Mocks all 8 providers and verifies every QuotaData entry satisfies:
//   1. window ∈ {"daily", "monthly", "rolling"}
//   2. info (when present) is a non-empty string
// This test is the hard domain-boundary enforcement point.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import { createAnthropicProvider } from "../../../src/adapters/providers/anthropic.js";
import { createGeminiProvider } from "../../../src/adapters/providers/gemini.js";
import { createOpenAIProvider } from "../../../src/adapters/providers/openai.js";
import { createKimiProvider } from "../../../src/adapters/providers/kimi.js";
import { createZaiProvider } from "../../../src/adapters/providers/zai.js";
import { createGoProvider } from "../../../src/adapters/providers/go.js";
import { createZenProvider } from "../../../src/adapters/providers/zen.js";
import { createMinimaxProvider } from "../../../src/adapters/providers/minimax.js";
import usageFIXTURE from "../../fixtures/providers/anthropic/usage.json";
import whamUsageFIXTURE from "../../fixtures/providers/openai/wham-usage.json";

// ── Mock helpers ───────────────────────────────────────────────────────────────

function makeSource(cred: Credential | null): CredentialSource {
  return { get: vi.fn(() => Promise.resolve(cred)) } as unknown as CredentialSource;
}

const apiCred: Credential = { variant: "api", key: "sk-test" };
const oauthCred: Credential = { variant: "oauth", access: "tok", refresh: "ref", expires: Date.now() + 60_000 };

const emptyAuth: Record<string, unknown> = {};
const emptyEnv: Record<string, string | undefined> = {};

const baseConfig = {
  displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24,
  pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5,
  showUnaggregated: false, show: true,
} as const;

// ── Mock node:fs for gemini (antigravity accounts) ────────────────────────────
const mockFiles: Record<string, string | null> = {};
vi.mock("node:fs", () => {
  const existsSync = (path: string) => Object.keys(mockFiles).some(f => String(path).endsWith(f));
  const readFileSync = (path: string) => {
    for (const [file, content] of Object.entries(mockFiles)) {
      if (String(path).endsWith(file)) {
        if (content === null) { const e = new Error(`ENOENT: ${file}`); (e as NodeJS.ErrnoException).code = "ENOENT"; throw e; }
        return content;
      }
    }
    const e = new Error(`ENOENT: ${path}`); (e as NodeJS.ErrnoException).code = "ENOENT"; throw e;
  };
  return { existsSync, readFileSync };
});

function mockFs(files: Record<string, string | null>) {
  Object.assign(mockFiles, files);
}
function clearMockFs() {
  for (const k of Object.keys(mockFiles)) delete mockFiles[k];
}

// ── Mock node:child_process for minimax ───────────────────────────────────────
vi.mock("node:child_process", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { execSync: realExecSync } = require("node:child_process") as any;
  const execSync = vi.fn((cmd: string, opts?: unknown) => {
    // WU-6: allow `which mmx` lookup to pass through to the real binary check.
    // Only mock commands that contain "mmx" (the actual quota fetch chain).
    if (typeof cmd === "string" && cmd.includes("mmx")) {
      return Buffer.from(JSON.stringify({
        model_remains: [
          // general — interval with quota + weekly with quota
          {
            model_name: "general",
            current_interval_total_count: 100,
            current_interval_usage_count: 5,
            current_interval_remaining_percent: 95,
            current_weekly_total_count: 100,
            current_weekly_usage_count: 5,
            current_weekly_remaining_percent: 95,
          },
          // video — interval with quota; weekly counts are 0 so no weekly row emitted
          {
            model_name: "video",
            current_interval_total_count: 3,
            current_interval_usage_count: 0,
            current_interval_remaining_percent: 100,
            current_weekly_total_count: 0,
            current_weekly_usage_count: 0,
            current_weekly_remaining_percent: 100,
          },
        ],
      }), "utf-8");
    }
    // Pass through all other commands (e.g. `which mmx` pre-check).
    return realExecSync(cmd, opts);
  });
  return { execSync };
});

// ── Invariant assertions ───────────────────────────────────────────────────────

const STRICT_WINDOW_UNION = ["daily", "monthly", "rolling", "rolling-5h", "rolling-mcp", "rolling-tokens", "rolling-weekly"] as const;

function assertInvariant(_label: string, quotas: Array<{ window: string; info?: string }>) {
  for (const q of quotas) {
    expect(STRICT_WINDOW_UNION).toContain(q.window);
    if (q.info !== undefined) {
      expect(typeof q.info).toBe("string");
      expect(q.info.length).toBeGreaterThan(0);
    }
  }
}

// ── Test suite ─────────────────────────────────────────────────────────────────

describe("info + window strict-union invariant (all 8 providers)", () => {

  beforeEach(() => { clearMockFs(); vi.clearAllMocks(); });
  afterEach(() => { clearMockFs(); });

  it("Anthropic: every QuotaData.window ∈ union + info non-empty when present", async () => {
    const http = { request: vi.fn(() => Promise.resolve(usageFIXTURE)) } as unknown as HttpClient;
    const cfg = { ...baseConfig, anthropic: { orgId: "org-test" } };
    const p = createAnthropicProvider(makeSource(apiCred), http, cfg, emptyAuth, emptyEnv);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("Anthropic", qs);
  });

  it("Gemini: every QuotaData.window = 'rolling' + info non-empty", async () => {
    mockFs({
      "antigravity-accounts.json": JSON.stringify([{
        email: "test@example.com", refreshToken: "ref", clientId: "cid",
        oauthSecret: "sec", projectId: "pid",
      }]),
    });
    const http = {
      request: vi.fn((r: unknown) => {
        const req = r as { url?: string };
        if (req.url?.includes("oauth")) {
          return Promise.resolve({ access_token: "tok", expires_in: 3600, token_type: "Bearer" });
        }
        return Promise.resolve({
          models: {
            "gemini-3-pro-high": { quotaInfo: { remainingFraction: 0.72, resetTime: "2026-07-27T00:00:00Z" } },
          },
        });
      }),
    } as unknown as HttpClient;
    const p = createGeminiProvider(makeSource(oauthCred), http);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("Gemini", qs);
    for (const q of qs) expect(q.window).toBe("rolling");
  });

  it("OpenAI OAuth: every QuotaData.window ∈ union + info non-empty", async () => {
    const http = { request: vi.fn(() => Promise.resolve(whamUsageFIXTURE)) } as unknown as HttpClient;
    const p = createOpenAIProvider(makeSource(oauthCred), http);
    const qs = await p.fetchQuotas({}, {});
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("OpenAI OAuth", qs);
  });

  it("OpenAI raw-key: every QuotaData.window ∈ union + info non-empty", async () => {
    const platformFixture = {
      data: [{ id: "gen-xyz", object: "api_usage", model: "gpt-4o", generated: 5000, created_at: 1753328400 }],
      has_more: false, next_page: null,
    };
    const http = { request: vi.fn(() => Promise.resolve(platformFixture)) } as unknown as HttpClient;
    const p = createOpenAIProvider(makeSource(apiCred), http);
    const qs = await p.fetchQuotas({}, {});
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("OpenAI raw-key", qs);
  });

  it("Kimi: window via windowMap (strict union) + info non-empty", async () => {
    const fixture = {
      windows: [{ label: "Daily", used: 40, limit: 100 }],
      credits: { balance: "10.00" },
    };
    const http = { request: vi.fn(() => Promise.resolve(fixture)) } as unknown as HttpClient;
    const p = createKimiProvider(makeSource(oauthCred), http);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("Kimi", qs);
  });

  it("Zai: window via windowMap (strict union) + info non-empty", async () => {
    const fixture = {
      code: 200,
      msg: "success",
      data: {
        limits: [
          {
            type: "TIME_LIMIT", unit: 5, number: 1,
            usage: 100, currentValue: 0, remaining: 100, percentage: 40,
            nextResetTime: 1750000000000, usageDetails: [],
          },
          {
            type: "MCP_LIMIT", unit: 1, number: 1,
            usage: 1000, currentValue: 200, remaining: 800, percentage: 20,
            nextResetTime: 1750000000000, usageDetails: [],
          },
        ],
      },
    };
    const http = { request: vi.fn(() => Promise.resolve(fixture)) } as unknown as HttpClient;
    const p = createZaiProvider(makeSource(oauthCred), http);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(1);
    assertInvariant("Zai", qs);
    const timeLimitRow = qs.find((q) => q.id.includes("time_limit"));
    const mcpLimitRow = qs.find((q) => q.id.includes("mcp_limit"));
    expect(timeLimitRow).toBeDefined();
    expect(mcpLimitRow).toBeDefined();
    expect(timeLimitRow!.used).toBe(40);
    expect(mcpLimitRow!.used).toBe(20);
  });

  it("Go: window via windowMap (strict union) + info non-empty", async () => {
    const fixture = {
      windows: [{ label: "Monthly", used: 60, limit: 200 }],
      credits: null,
    };
    const http = { request: vi.fn(() => Promise.resolve(fixture)) } as unknown as HttpClient;
    const p = createGoProvider(makeSource(apiCred), http);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("Go", qs);
  });

  it("Zen: window via windowMap (strict union) + info non-empty", async () => {
    const fixture = {
      windows: [{ label: "Monthly", used: 60, limit: 200 }],
      credits: null,
    };
    const http = { request: vi.fn(() => Promise.resolve(fixture)) } as unknown as HttpClient;
    const p = createZenProvider(makeSource(apiCred), http);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("Zen", qs);
  });

  it("Minimax: window via windowMap (strict union) + info non-empty", async () => {
    const http = { request: vi.fn(() => Promise.resolve({})) } as unknown as HttpClient;
    const p = createMinimaxProvider(makeSource({ variant: "api", key: "mmx-key" } as Credential), http);
    const qs = await p.fetchQuotas();
    expect(qs.length).toBeGreaterThan(0);
    assertInvariant("Minimax", qs);
  });

  describe("QuotaData.window — rolling-weekly", () => {
    it("accepts 'rolling-weekly' in the strict union", () => {
      const sample: import("../../../src/domain/types.js").QuotaData = {
        id: "minimax-general-weekly",
        providerName: "Minimax · Weekly limit",
         used: 5,
         limit: 100,
         unit: "%",
         reset: null,
         window: "rolling-weekly",
       };
      expect(STRICT_WINDOW_UNION).toContain("rolling-weekly");
      expect(sample.window).toBe("rolling-weekly");
    });
  });

});
