// RED → GREEN: OpenAI provider — oauth + api variants, 401 refresh, failure isolation.
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

  // ── api: platform usage ───────────────────────────────────────────────────
  it("api: parses platform usage and uses Bearer token", async () => {
    let capturedReq: unknown;
    const http = { request: vi.fn((r: unknown) => { capturedReq = r; return Promise.resolve(platformUsageFIXTURE); }) } as unknown as HttpClient;
    const qs = await createOpenAIProvider(makeSource(() => Promise.resolve(apiCred)), http).fetchQuotas({}, {});
    expect((capturedReq as { headers?: Record<string, string> }).headers?.Authorization).toBe("Bearer sk-test");
    expect(qs).toHaveLength(1);
    expect(qs[0]).toMatchObject({ id: "openai-api-usage", used: 142857, limit: 100000000, unit: "tokens" });
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
});
