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

  // ── WU-2: semantic labels — no raw type/tuple leakage ─────────────────────────
  it("parseZaiLimits: TIME_LIMIT 5h row → info contains '5-hour rolling limit', providerName uses · separator", async () => {
    const http = {
      request: vi.fn(() => Promise.resolve({
        code: 200, msg: "success",
        data: { limits: [{
          type: "TIME_LIMIT", unit: 5, number: 1,
          usage: 100, currentValue: 0, remaining: 100,
          percentage: 12, nextResetTime: 1750000000000, usageDetails: [],
        }] },
      })),
    } as unknown as HttpClient;
    const provider = createZaiProvider(makeSource(oauthCred), http);
    const quotas = await provider.fetchQuotas();
    expect(quotas.length).toBeGreaterThan(0);
    const row = quotas.find((q) => q.id.includes("time_limit"))!;
    // info must be the human label, not "TIME_LIMIT (1×5)"
    expect(row.info).toContain("5-hour rolling limit");
    // providerName must use the · separator
    expect(row.providerName).toContain("\u00A0·\u00A0");
    // Must NOT leak raw type or numeric tuple
    expect(row.info).not.toContain("TIME_LIMIT");
    expect(row.info).not.toContain("(1×5)");
  });

  it("parseZaiLimits: MCP_LIMIT row → info contains 'MCP quota', no MCP_LIMIT leakage", async () => {
    const http = {
      request: vi.fn(() => Promise.resolve({
        code: 200, msg: "success",
        data: { limits: [{
          type: "MCP_LIMIT", unit: 1, number: 1,
          usage: 1000, currentValue: 200, remaining: 800,
          percentage: 20, nextResetTime: 1750000000000, usageDetails: [],
        }] },
      })),
    } as unknown as HttpClient;
    const provider = createZaiProvider(makeSource(oauthCred), http);
    const quotas = await provider.fetchQuotas();
    const mcpRow = quotas.find((q) => q.id.includes("mcp_limit"))!;
    expect(mcpRow.info).toContain("MCP quota");
    expect(mcpRow.info).not.toContain("MCP_LIMIT");
    expect(mcpRow.info).not.toContain("(1×1)");
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