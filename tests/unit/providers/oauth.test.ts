// RED → GREEN: shared OAuth helper — Bearer header, 401 single-refresh + retry.
import { describe, it, expect, vi } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import { withOAuth } from "../../../src/adapters/providers/oauth.js";

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
});
