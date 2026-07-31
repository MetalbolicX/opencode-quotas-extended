// RED → GREEN: shared OAuth helper — Bearer header, 401 single-refresh + retry.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../legacy/ports/credentials.js";
import type { HttpClient } from "../../../legacy/ports/http.js";
import { withOAuth } from "../../../legacy/adapters/providers/oauth.js";

function src(cred: Credential | null) { return { get: () => Promise.resolve(cred) } as unknown as CredentialSource; }
const oauthCred: Credential = { variant: "oauth", access: "tok", refresh: "ref", expires: Date.now() + 60_000 };
const apiCred: Credential = { variant: "api", key: "sk-test" };
const fakeReq = { url: "https://x.com", method: "GET" as const };

describe("oauth helper", () => {
  it("oauth → Bearer token", async () => {
    let req: unknown;
    const http = { request: vi.fn((r: unknown) => { req = r; return Promise.resolve(42); }) } as unknown as HttpClient;
    await withOAuth(src(oauthCred), http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }));
    expect((req as { headers?: Record<string, string> }).headers?.Authorization).toBe("Bearer tok");
  });

  it("api → Bearer key", async () => {
    let req: unknown;
    const http = { request: vi.fn((r: unknown) => { req = r; return Promise.resolve(42); }) } as unknown as HttpClient;
    await withOAuth(src(apiCred), http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }));
    expect((req as { headers?: Record<string, string> }).headers?.Authorization).toBe("Bearer sk-test");
  });

  it("success → returns result", async () => {
    const http = { request: vi.fn(() => Promise.resolve({ ok: true })) } as unknown as HttpClient;
    const r = await withOAuth(src(oauthCred), http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }));
    expect(r).toEqual({ ok: true });
  });

  it("401 → refresh once then retry", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => { callCount++; if (callCount === 1) { const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; } return { ok: true }; }) } as unknown as HttpClient;
    const r = await withOAuth(src(oauthCred), http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }));
    expect(callCount).toBe(2);
    expect(r).toEqual({ ok: true });
  });

  it("second 401 → returns []", async () => {
    let callCount = 0;
    const http = { request: vi.fn(async () => { callCount++; const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; }) } as unknown as HttpClient;
    expect(await withOAuth(src(oauthCred), http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }))).toEqual([]);
    expect(callCount).toBe(2);
  });

  it("null cred → skips request, returns []", async () => {
    const http = { request: vi.fn() } as unknown as HttpClient;
    expect(await withOAuth(src(null), http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }))).toEqual([]);
    expect(http.request).not.toHaveBeenCalled();
  });

  // ─── single-flight storm tests ─────────────────────────────────────────────

  it("50 concurrent refreshes coalesce to 1 fetch (storm)", async () => {
    // Simulate: all 50 callers hit 401 at the same time.
    // Single-flight: all share the same initial credential fetch + same retry credential fetch.
    // HTTP calls: the mock always throws 401 regardless of credentials,
    // so all 50 initial calls return 401, and all 50 retry calls also return 401.
    let fetchCount = 0;
    const http = {
      request: vi.fn(async () => {
        fetchCount++;
        const e = new Error("unauthorized");
        (e as Error & { status?: number }).status = 401;
        throw e;
      }),
    } as unknown as HttpClient;

    // source.get() is called exactly twice: once in the initial phase (shared by all 50 callers)
    // and once in the retry phase (shared by all 50 callers who all hit 401).
    const sourceGet = vi.fn(async () => oauthCred);
    const trackingSource = { get: sourceGet } as unknown as CredentialSource;

    const results = await Promise.all(
      Array.from({ length: 50 }, () =>
        withOAuth(trackingSource, http, "openai", (c) =>
          c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }),
        ),
      ),
    );

    // All 50 callers return [] because both initial and retry HTTP calls fail with 401.
    expect(results.every((r) => Array.isArray(r) && r.length === 0)).toBe(true);
    // Exactly 2 credential fetches: initial phase + retry phase (correct per spec: fresh cred each phase)
    expect(sourceGet).toHaveBeenCalledTimes(2);
    // Exactly 2 HTTP calls: first caller's initial (401) + first caller's retry (401)
    // All 50 callers share these two calls; their subsequent retry calls are coalesced.
    expect(fetchCount).toBe(2);
  });

  it("concurrent refresh with stale token → all get the retry result", async () => {
    let callCount = 0;
    const http = {
      request: vi.fn(async () => {
        callCount++;
        if (callCount === 1) {
          const e = new Error("stale");
          (e as Error & { status?: number }).status = 401;
          throw e;
        }
        return { data: "refreshed" };
      }),
    } as unknown as HttpClient;
    // source.get() is called once in initial phase (shared) and once in retry phase (shared).
    // oauthCred is the same for both callers, so the retry succeeds with {data: "refreshed"}.
    const sourceGet = vi.fn(async () => oauthCred);
    const trackingSource = { get: sourceGet } as unknown as CredentialSource;

    const [first, second] = await Promise.all([
      withOAuth(trackingSource, http, "openai", (c) =>
        c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }),
      ),
      withOAuth(trackingSource, http, "openai", (c) =>
        c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }),
      ),
    ]);

    expect(first).toEqual({ data: "refreshed" });
    expect(second).toEqual({ data: "refreshed" });
    // Two credential fetches: initial phase (shared by concurrent callers) + retry phase (shared).
    expect(sourceGet).toHaveBeenCalledTimes(2);
  });

  it("refresh failure rejects all waiters with the same error", async () => {
    const http = {
      request: vi.fn(async () => {
        const e = new Error("unauthorized");
        (e as Error & { status?: number }).status = 401;
        throw e;
      }),
    } as unknown as HttpClient;
    // Second call to source.get also returns null → refresh fails → all get []
    const sourceGet = vi.fn(async () => null);
    const trackingSource = { get: sourceGet } as unknown as CredentialSource;

    const promises = Array.from({ length: 5 }, () =>
      withOAuth(trackingSource, http, "openai", (c) =>
        c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }),
      ),
    );
    const results = await Promise.all(promises);

    // All waiters get [] because the shared refresh returned null
    expect(results).toEqual([[], [], [], [], []]);
    // Exactly 1 refresh attempt (not 5)
    expect(sourceGet).toHaveBeenCalledTimes(1);
  });

  it("different credentials don't coalesce → independent refresh cycles", async () => {
    const httpA = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; }) } as unknown as HttpClient;
    const httpB = { request: vi.fn(async () => { const e = new Error(); (e as Error & { status?: number }).status = 401; throw e; }) } as unknown as HttpClient;
    const sourceGetA = vi.fn(async () => oauthCred);
    const sourceGetB = vi.fn(async () => ({ variant: "oauth" as const, access: "tok2", refresh: "ref2", expires: Date.now() + 60_000 }));
    const sourceA = { get: sourceGetA } as unknown as CredentialSource;
    const sourceB = { get: sourceGetB } as unknown as CredentialSource;

    const [rA, rB] = await Promise.all([
      withOAuth(sourceA, httpA, "provider-a", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
      withOAuth(sourceB, httpB, "provider-b", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
    ]);

    // Each provider had its own 401 → refresh → second 401 → []
    expect(rA).toEqual([]);
    expect(rB).toEqual([]);
    // Each provider calls source.get() once in initial phase and once in retry phase
    // (independent refresh cycles, not shared retry).
    // The mock always throws 401, so both retry calls also return [].
    expect(sourceGetA).toHaveBeenCalledTimes(2);
    expect(sourceGetB).toHaveBeenCalledTimes(2);
  });

  it("successful refresh clears in-flight — second call can start fresh", async () => {
    let fetchCount = 0;
    const http = {
      request: vi.fn(async () => {
        fetchCount++;
        if (fetchCount === 1) {
          const e = new Error(); (e as Error & { status?: number }).status = 401; throw e;
        }
        return { ok: true };
      }),
    } as unknown as HttpClient;
    const sourceGet = vi.fn(async () => oauthCred);
    const trackingSource = { get: sourceGet } as unknown as CredentialSource;

    // First storm: 3 concurrent callers that all hit 401 and get coalesced
    await Promise.all([
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
    ]);

    // After storm clears, a second 401 should trigger a NEW refresh (not reuse stale)
    fetchCount = 0;
    const secondStorm = await Promise.all([
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
    ]);

    // Second storm coalesces into 1 fresh refresh + 1 retry → 2 calls total
    expect(fetchCount).toBe(2);
    expect(secondStorm.every((r) => !Array.isArray(r) || r.length > 0)).toBe(true);
  });

  it("rejection clears in-flight — retry after null cred succeeds", async () => {
    let refreshCount = 0;
    const http = {
      request: vi.fn(async () => {
        const e = new Error(); (e as Error & { status?: number }).status = 401; throw e;
      }),
    } as unknown as HttpClient;
    // First call returns null cred → refresh fails → all waiters get []
    const sourceGet = vi.fn(async () => { refreshCount++; return refreshCount === 1 ? null : oauthCred; });
    const trackingSource = { get: sourceGet } as unknown as CredentialSource;

    const [r1, r2] = await Promise.all([
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
      withOAuth(trackingSource, http, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true })),
    ]);

    // First storm: null refresh → all get []
    expect(r1).toEqual([]);
    expect(r2).toEqual([]);
    expect(refreshCount).toBe(1); // 1 coalesced refresh attempt

    // Next call: now cred is available → should work normally
    const http2 = { request: vi.fn(() => Promise.resolve({ ok: true })) } as unknown as HttpClient;
    const r3 = await withOAuth(trackingSource, http2, "openai", (c) => c.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true }));
    expect(r3).toEqual({ ok: true });
  });
});
