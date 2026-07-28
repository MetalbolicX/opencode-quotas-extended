// RED → GREEN → REFACTOR: OpenAI provider — oauth + api variants, 401 refresh, failure isolation.
// Slice 9: raw-key /v1/usage pagination — cursor-based loop, cap 20, failure isolation, first-wins dedup.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import { createOpenAIProvider } from "../../../src/adapters/providers/openai.js";
import whamUsageFIXTURE from "../../../tests/fixtures/providers/openai/wham-usage.json";
import platformUsageFIXTURE from "../../../tests/fixtures/providers/openai/platform-usage.json";

function makeSource(getFn: () => Promise<Credential | null>): CredentialSource {
  return { get: getFn } as CredentialSource;
}

const oauthCred: Credential = { variant: "oauth", access: "tok", refresh: "ref", expires: Date.now() + 60_000 };
const apiCred: Credential = { variant: "api", key: "sk-test" };

describe("openai-provider", () => {
  // ── isAvailable ───────────────────────────────────────────────────────────
  it.each([
    { label: "oauth", cred: oauthCred, exp: true },
    { label: "api", cred: apiCred, exp: true },
    { label: "null", cred: null, exp: false },
  ])("isAvailable: $label → $exp", async ({ cred, exp }) => {
    const provider = createOpenAIProvider(makeSource(() => Promise.resolve(cred)), { request: vi.fn() } as unknown as HttpClient);
    expect(await provider.isAvailable({}, {})).toBe(exp);
  });

  // ── oauth: wham/usage ────────────────────────────────────────────────────
  it("oauth: parses wham/usage and uses Bearer token", async () => {
    let capturedReq: unknown;
    const http = { request: vi.fn((r: unknown) => { capturedReq = r; return Promise.resolve(whamUsageFIXTURE); }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
    expect((capturedReq as { headers?: Record<string, string> }).headers?.Authorization).toBe("Bearer tok");
    expect(qs).toHaveLength(3);
    expect(qs.map((q) => q.id)).toEqual(["openai-primary", "openai-secondary", "openai-credits"]);
    const primary = qs.find((q) => q.id === "openai-primary")!;
    expect(primary).toMatchObject({ used: 73.5, limit: 100, unit: "%" });
    const credits = qs.find((q) => q.id === "openai-credits")!;
    expect(credits).toMatchObject({ used: 8.5, unit: "credits", limit: null });
  });

  // ── WU-2: semantic labels — no raw type leakage, · separator ──────────────────
  describe("openai — WU-2 semantic label enrichment", () => {
    it("oauth primary row: info = 'Primary rate limit', uses · separator, no raw 'primary'", async () => {
      const http = { request: vi.fn(() => Promise.resolve(whamUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
      const primary = qs.find((q) => q.id === "openai-primary")!;
      expect(primary.info).toBe("Primary rate limit");
      expect(primary.providerName).toContain("\u00A0·\u00A0");
      expect(primary.info).not.toContain("primary");
    });

    it("oauth secondary row: info = 'Secondary rate limit', no raw 'secondary'", async () => {
      const http = { request: vi.fn(() => Promise.resolve(whamUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
      const secondary = qs.find((q) => q.id === "openai-secondary")!;
      expect(secondary.info).toBe("Secondary rate limit");
      expect(secondary.info).not.toContain("secondary");
    });

    it("oauth credits row: info = 'Credit balance', no raw 'unlimited' or 'balance'", async () => {
      const http = { request: vi.fn(() => Promise.resolve(whamUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
      const credits = qs.find((q) => q.id === "openai-credits")!;
      expect(credits.info).toBe("Credit balance");
      expect(credits.info).not.toContain("unlimited");
    });

    it("api per-model row: info = 'Token usage', window is rolling, no model leakage in info", async () => {
      const http = { request: vi.fn(() => Promise.resolve(platformUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
      expect(qs.length).toBeGreaterThan(0);
      for (const q of qs) {
        expect(q.info).toBe("Token usage");
        expect(q.window).toBe("rolling");
      }
    });
  });

  // ── Slice 12: info + window strict union assertions ─────────────────────
  describe("openai — info + window strict union (slice 12)", () => {
    it("oauth primary/secondary: window is strict union + info is non-empty string", async () => {
      const http = { request: vi.fn(() => Promise.resolve(whamUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
      const primary = qs.find((q) => q.id === "openai-primary")!;
      const secondary = qs.find((q) => q.id === "openai-secondary")!;
      // window must be from strict union
      expect(["daily", "monthly", "rolling"]).toContain(primary.window);
      expect(["daily", "monthly", "rolling"]).toContain(secondary.window);
      // info must be non-empty string
      expect(typeof primary.info).toBe("string");
      expect(primary.info!.length).toBeGreaterThan(0);
      expect(typeof secondary.info).toBe("string");
      expect(secondary.info!.length).toBeGreaterThan(0);
    });

    it("oauth credits: window is strict union + info is non-empty string", async () => {
      const http = { request: vi.fn(() => Promise.resolve(whamUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
      const credits = qs.find((q) => q.id === "openai-credits")!;
      expect(["daily", "monthly", "rolling"]).toContain(credits.window);
      expect(typeof credits.info).toBe("string");
      expect(credits.info!.length).toBeGreaterThan(0);
    });

    it("raw-key: window is strict union + info is non-empty string", async () => {
      const http = { request: vi.fn(() => Promise.resolve(platformUsageFIXTURE)) } as unknown as HttpClient;
      const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
      expect(qs.length).toBeGreaterThan(0);
      for (const q of qs) {
        expect(["daily", "monthly", "rolling"]).toContain(q.window);
        expect(typeof q.info).toBe("string");
        expect(q.info!.length).toBeGreaterThan(0);
      }
    });
  });

  // ── api: platform usage ───────────────────────────────────────────────────
  it("api: parses platform usage and uses Bearer token", async () => {
    let capturedReq: unknown;
    const http = { request: vi.fn((r: unknown) => { capturedReq = r; return Promise.resolve(platformUsageFIXTURE); }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect((capturedReq as { headers?: Record<string, string> }).headers?.Authorization).toBe("Bearer sk-test");
    expect(qs).toHaveLength(1);
    // id is openai-api-{entry.id} per pagination dedup spec; entry.id from fixture = "gen-abc123"
    expect(qs[0]).toMatchObject({ id: "openai-api-gen-abc123", used: 142857, limit: 100000000, unit: "tokens" });
  });

  // ── api: 401 → [ ] ───────────────────────────────────────────────────────
  it("api: on 401 returns [] (no throw)", async () => {
    const http = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; }) } as unknown as HttpClient;
    // Must not throw; should return [] for api-key variant on 401
    await expect(createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {})).resolves.toEqual([]);
  });

  // ── 401 refresh ───────────────────────────────────────────────────────────
  it("on 401: refreshes once then retries → QuotaData[]", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => { callCount++; if (callCount === 1) { const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; } return whamUsageFIXTURE; }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(2);
    expect(qs).toHaveLength(3);
  });

  it("on second 401: returns [] (no third retry)", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => { callCount++; const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; }) } as unknown as HttpClient;
    expect(await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {})).toEqual([]);
    expect(callCount).toBe(2);
  });

  // ── HTTP failures ────────────────────────────────────────────────────────
  it.each([
    { label: "HTTP 500", status: 500 },
    { label: "network error", err: "ENOTFOUND" },
  ])("on $label: returns [] (no throw)", async ({ status, err }) => {
    const http = { request: status != null
      ? vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = status; throw e; })
      : vi.fn(() => Promise.reject(new Error(err))) } as unknown as HttpClient;
    expect(await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {})).toEqual([]);
  });

  // ── Slice 9: raw-key /v1/usage pagination ──────────────────────────────────

  // Scenario 1: Single page — has_more=false, next_page=null → returns entries, no second request
  it("api pagination: single page (has_more=false) returns entries and makes no second request", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => { callCount++; return { total_usage: 1000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 1000, created_at: 1753328400 }], has_more: false, next_page: null }; }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(1);
    expect(qs).toHaveLength(1);
    expect(qs[0].used).toBe(1000);
  });

  // Scenario 2: Two pages — page 1 has_more=true + next_page="abc"; page 2 terminal → both aggregated
  it("api pagination: two pages aggregated — page 1 has_more=true, page 2 terminal", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => {
      callCount++;
      if (callCount === 1) {
        return { total_usage: 1000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 1000, created_at: 1753328400 }], has_more: true, next_page: "abc" };
      }
      return { total_usage: 2000, data: [{ id: "gen-2", object: "api_usage", model: "gpt-4o-mini", generated: 2000, created_at: 1753328500 }], has_more: false, next_page: null };
    }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(2);
    expect(qs).toHaveLength(2);
    expect(qs.map(q => q.used)).toEqual([1000, 2000]);
  });

  // Scenario 3: Infinite has_more → loop terminates at cap (20); only 20 requests made
  it("api pagination: infinite has_more loop terminates at cap 20", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => {
      callCount++;
      return { total_usage: callCount * 100, data: [{ id: `gen-${callCount}`, object: "api_usage", model: "gpt-4o", generated: callCount * 100, created_at: 1753328400 + callCount }], has_more: true, next_page: `page-${callCount}` };
    }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(20);
    expect(qs).toHaveLength(20);
  });

  // Scenario 4: Pagination failure isolation — page 1 ok, page 2 throws → page 1 entries returned, no throw
  it("api pagination: page 1 ok, page 2 throws → page 1 entries returned, no throw", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => {
      callCount++;
      if (callCount === 1) {
        return { total_usage: 1000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 1000, created_at: 1753328400 }], has_more: true, next_page: "abc" };
      }
      const e = new Error("server error");
      (e as Error & { status?: number }).status = 500;
      throw e;
    }) } as unknown as HttpClient;
    await expect(createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {})).resolves.toHaveLength(1);
    expect(callCount).toBe(2);
  });

  // Scenario 5: OAuth WHAM path unchanged — no pagination on OAuth variant
  it("oauth: wham/usage path does NOT paginate (single request, unchanged from slice 1)", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => { callCount++; return whamUsageFIXTURE; }) } as unknown as HttpClient;
    await createOpenAIProvider(makeSource(() => Promise.resolve(oauthCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(1);
  });

  // Scenario 6: Defensive parse — malformed has_more/next_page treated as terminal
  it("api pagination: malformed has_more/next_page treated as terminal — no second request", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => {
      callCount++;
      // has_more is a string instead of boolean — should be treated as falsy (terminal)
      return { total_usage: 1000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 1000, created_at: 1753328400 }], has_more: "yes" as unknown as boolean, next_page: 123 as unknown as string };
    }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(1);
    expect(qs).toHaveLength(1);
  });

  // Scenario 7: next_page present but has_more=false → terminal, no second request
  it("api pagination: next_page present but has_more=false → terminal, no second request", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => {
      callCount++;
      // has_more is explicitly false but next_page is also set — should still terminate
      return { total_usage: 1000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 1000, created_at: 1753328400 }], has_more: false, next_page: "should-ignore" };
    }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect(callCount).toBe(1);
    expect(qs).toHaveLength(1);
  });

  // Scenario 8: Aggregate dedup by id — first write wins on duplicate id across pages
  it("api pagination: duplicate id across pages → first write wins (first page value kept)", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => {
      callCount++;
      if (callCount === 1) {
        return { total_usage: 1000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 1000, created_at: 1753328400 }], has_more: true, next_page: "abc" };
      }
      // Same id appears on page 2 with different used value — first wins
      return { total_usage: 3000, data: [{ id: "gen-1", object: "api_usage", model: "gpt-4o", generated: 9999, created_at: 1753328500 }], has_more: false, next_page: null };
    }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect(qs).toHaveLength(1);
    // First page value (1000) wins, not 9999 from page 2
    expect(qs[0].used).toBe(1000);
  });
});
