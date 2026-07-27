// RED: z.ai provider — fixture-driven and stubbed HttpClient coverage.
import { describe, it, expect, vi } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import type { Logger } from "../../../src/ports/logger.js";
import { createZaiProvider } from "../../../src/adapters/providers/zai.js";

const FIXTURE = JSON.parse(
  readFileSync(
    join(process.cwd(), "tests/fixtures/providers/zai/usage.json"),
    "utf-8",
  ),
);

function makeSource(cred: Credential | null): CredentialSource {
  return { get: vi.fn(() => Promise.resolve(cred)) } as unknown as CredentialSource;
}

const oauthCred: Credential = {
  variant: "oauth",
  access: "acc",
  refresh: "ref",
  expires: 0,
};

describe("zai provider", () => {
  it("isAvailable returns true when zai-coding-plan credential is present", async () => {
    const http = {} as unknown as HttpClient;
    const provider = createZaiProvider(makeSource(oauthCred), http);
    expect(await provider.isAvailable()).toBe(true);
  });

  it("isAvailable returns false when no credential", async () => {
    const http = {} as unknown as HttpClient;
    const provider = createZaiProvider(makeSource(null), http);
    expect(await provider.isAvailable()).toBe(false);
  });

  it("fetchQuotas returns ≥1 row from a real z.ai-shaped response", async () => {
    // Stub HttpClient to return the fixture.
    const http = {
      request: vi.fn(() => Promise.resolve(FIXTURE)),
    } as unknown as HttpClient;
    const provider = createZaiProvider(makeSource(oauthCred), http);
    const quotas = await provider.fetchQuotas();
    expect(quotas.length).toBeGreaterThan(0);
    expect(quotas[0].providerName.toLowerCase()).toContain("z.ai");
  });

  it("fetchQuotas returns [] and logs when the HTTP layer throws", async () => {
    const mockLogger: Logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };
    const http = {
      request: vi.fn(() => Promise.reject(new Error("network down"))),
    } as unknown as HttpClient;
    const provider = createZaiProvider(makeSource(oauthCred), http, mockLogger);
    const quotas = await provider.fetchQuotas();
    expect(quotas).toEqual([]);
    expect(mockLogger.error).toHaveBeenCalled();
  });
});