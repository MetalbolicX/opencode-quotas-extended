// RED → GREEN: shared OAuth helper with 401 single-refresh + retry.
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient, HttpRequest } from "../../../src/ports/http.js";
import { withOAuth } from "../../../src/adapters/providers/oauth.js";

function makeSource(getFn: () => Promise<Credential | null>): CredentialSource {
  return { get: getFn } as CredentialSource;
}

const oauthCred: Credential = {
  variant: "oauth",
  access: "access_token_123",
  refresh: "refresh_token_456",
  expires: Date.now() + 60_000,
};

const apiCred: Credential = {
  variant: "api",
  key: "sk-openai-test-key",
};

const fakeReq: HttpRequest = {
  url: "https://chatgpt.com/backend-api/wham/usage",
  method: "GET",
};

describe("oauth helper — withOAuth", () => {
  it("sets Bearer Authorization header for oauth credential", async () => {
    const source = makeSource(() => Promise.resolve(oauthCred));
    let capturedReq: HttpRequest | undefined;
    const http = {
      request: vi.fn(async (req: HttpRequest) => {
        capturedReq = req;
        return { ok: true };
      }),
    } as unknown as HttpClient;

    await withOAuth(source, http, "openai", async (client) => {
      return client.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true });
    });

    expect(capturedReq?.headers?.["Authorization"]).toBe("Bearer access_token_123");
  });

  it("sets Authorization header with API key for api credential", async () => {
    const source = makeSource(() => Promise.resolve(apiCred));
    let capturedReq: HttpRequest | undefined;
    const http = {
      request: vi.fn(async (req: HttpRequest) => {
        capturedReq = req;
        return { ok: true };
      }),
    } as unknown as HttpClient;

    await withOAuth(source, http, "openai", async (client) => {
      return client.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true });
    });

    expect(capturedReq?.headers?.["Authorization"]).toBe("Bearer sk-openai-test-key");
  });

  it("returns result from successful oauth request", async () => {
    const source = makeSource(() => Promise.resolve(oauthCred));
    const expected = { rate_limit: { primary_window: {} } };
    const http = { request: vi.fn(() => Promise.resolve(expected)) } as unknown as HttpClient;

    const result = await withOAuth(source, http, "openai", async (client) => {
      return client.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true });
    });

    expect(result).toEqual(expected);
  });

  it("on 401: refreshes once then retries", async () => {
    let callCount = 0;
    const source = makeSource(() => {
      callCount++;
      return Promise.resolve(callCount === 1 ? oauthCred : { ...oauthCred, access: "refreshed_token" });
    });

    const responses: unknown[] = [];
    let reqCount = 0;
    const http = {
      request: vi.fn(async () => {
        reqCount++;
        if (reqCount === 1) {
          const err = new Error("401") as Error & { status?: number };
          err.status = 401;
          throw err;
        }
        return { ok: true, refreshed: true };
      }),
    } as unknown as HttpClient;

    const result = await withOAuth(source, http, "openai", async (client) => {
      return client.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true });
    });

    expect(reqCount).toBe(2);
    expect(result).toEqual({ ok: true, refreshed: true });
  });

  it("on second 401 after refresh: returns [] and does not retry again", async () => {
    let reqCount = 0;
    const source = makeSource(() => Promise.resolve(oauthCred));
    const http = {
      request: vi.fn(async () => {
        reqCount++;
        const err = new Error("401") as Error & { status?: number };
        err.status = 401;
        throw err;
      }),
    } as unknown as HttpClient;

    const result = await withOAuth(source, http, "openai", async (client) => {
      return client.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true });
    });

    // Only 2 calls: original (401) + refresh (401) — no third retry
    expect(reqCount).toBe(2);
    expect(result).toEqual([]);
  });

  it("when credential is null: skips request and returns []", async () => {
    const source = makeSource(() => Promise.resolve(null));
    const http = { request: vi.fn() } as unknown as HttpClient;

    const result = await withOAuth(source, http, "openai", async (client) => {
      return client.request(fakeReq, { timeoutMs: 5000, retries: 0, redact: true });
    });

    expect(result).toEqual([]);
    expect(http.request).not.toHaveBeenCalled();
  });
});
