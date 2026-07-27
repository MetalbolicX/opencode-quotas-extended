// WU-6 RED: Minimax provider — missing mmx binary returns []{+logs error}.
// REQ-CRED-5: friendly error when mmx CLI is absent from PATH.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { Credential, CredentialSource } from "../../../src/ports/credentials.js";
import type { HttpClient } from "../../../src/ports/http.js";
import type { Logger } from "../../../src/ports/logger.js";
import { createMinimaxProvider } from "../../../src/adapters/providers/minimax.js";

function makeSource(cred: Credential | null): CredentialSource {
  return { get: vi.fn(() => Promise.resolve(cred)) } as unknown as CredentialSource;
}

const apiCred: Credential = { variant: "api", key: "sk-test-mmx" };

// Mock node:child_process — simulates mmx binary NOT in PATH (which throws).
// The actual implementation uses `execSync("which", ["mmx"])` to pre-check.
// We mock execSync to throw with ENOENT so the pre-check catches it.
vi.mock("node:child_process", () => ({
  execSync: vi.fn((_cmd: string, _opts?: unknown) => {
    // When mmx is not found, "which mmx" throws with code "ENOENT".
    const err = new Error("spawn mmx ENOENT");
    (err as NodeJS.ErrnoException).code = "ENOENT";
    throw err;
  }),
}));

describe("minimax provider — mmx binary pre-check (WU-6)", () => {
  let mockLogger: Logger;

  beforeEach(() => {
    mockLogger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // ── fetchQuotas: mmx absent ─────────────────────────────────────────────────

  it("fetchQuotas returns [] when mmx is NOT in PATH and logs error", async () => {
    const http = {} as unknown as HttpClient;
    const provider = createMinimaxProvider(makeSource(apiCred), http, mockLogger);

    const quotas = await provider.fetchQuotas();

    // Should return empty array (no throw)
    expect(quotas).toEqual([]);

    // Logger must be called with an error that mentions mmx
    expect(mockLogger.error).toHaveBeenCalled();
    const errorCall = (mockLogger.error as ReturnType<typeof vi.fn>).mock.calls.find(
      (call) => String(call[0] ?? "").includes("mmx") || String(call[1] ?? "").includes("mmx"),
    );
    expect(errorCall).toBeDefined();
  });

  it("fetchQuotas returns [] when there are no credentials (already covered but belt-and-suspenders)", async () => {
    const http = {} as unknown as HttpClient;
    const provider = createMinimaxProvider(makeSource(null), http, mockLogger);

    const quotas = await provider.fetchQuotas();

    expect(quotas).toEqual([]);
  });
});
