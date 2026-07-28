// WU-2 RED: CLI --list mode tests.
// REQ-LIST-1..7: numbered provider table for picker UX.
// D-4: list layout via existing TableRenderer with synthetic QuotaData.
import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import type { QuotaProvider } from "../../../src/ports/provider.js";

// ── stdout/stderr capture ────────────────────────────────────────────────────

let stdout = "", stderr = "";
beforeEach(() => {
  stdout = ""; stderr = "";
  vi.spyOn(process.stdout, "write").mockImplementation((c: string) => (stdout += String(c), true));
  vi.spyOn(process.stderr, "write").mockImplementation((c: string) => (stderr += String(c), true));
});
afterEach(() => { vi.restoreAllMocks(); });

// ── Module mocks (hoisted to top, applied before imports) ─────────────────

const { mockBuildDefaultRegistry } = vi.hoisted(() => {
  const mockProviders: QuotaProvider[] = [
    {
      id: "openai",
      displayName: "OpenAI",
      category: "api-spend",
      authStrategy: "api",
      isAvailable: () => Promise.resolve(true),
      fetchQuotas: () => Promise.resolve([]),
    },
    {
      id: "anthropic",
      displayName: "Anthropic",
      category: "api-spend",
      authStrategy: "api",
      isAvailable: () => Promise.resolve(true),
      fetchQuotas: () => Promise.resolve([]),
    },
  ];
  const mockReg = {
    list: () => mockProviders,
    get: (id: string) => mockProviders.find((p) => p.id === id),
  };
  return { mockBuildDefaultRegistry: vi.fn(() => mockReg) };
});

vi.mock("../../../src/adapters/providers/registry.js", () => ({
  buildDefaultRegistry: mockBuildDefaultRegistry,
}));

vi.mock("../../../src/adapters/infra/config-loader.js", () => ({
  DEFAULTS: { displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } },
  loadConfig: vi.fn(() => ({ displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } })),
}));

vi.mock("../../../src/adapters/auth/credential-resolver.js", () => ({
  createCredentialResolver: vi.fn(() => ({ get: () => Promise.resolve(null) })),
}));

vi.mock("../../../src/adapters/infra/fetch-http.js", () => ({
  FetchHttpClient: vi.fn().mockImplementation(function () { this.request = vi.fn(); }),
}));

// ── Import after mocks are set up ───────────────────────────────────────────

import { run } from "../../../src/cli/index.js";
import { parseArgs } from "../../../src/cli/parse-args.js";

// ── Tests ───────────────────────────────────────────────────────────────────

describe("CLI --list mode", () => {
  describe("parseArgs", () => {
    it("extends CliArgs with list: boolean", () => {
      const args = parseArgs(["-l"]);
      expect(args).toHaveProperty("list", true);
    });

    it("list defaults to true (REQ-CLI-1)", () => {
      const args = parseArgs([]);
      expect(args.list).toBe(true);
    });

    it("rejects -l when -p is also present (mutual exclusion, REQ-CLI-4)", async () => {
      const result = await run(["-l", "-p", "openai"]);
      expect(result.exitCode).toBe(2);
      expect(result.stderr.toLowerCase()).toContain("cannot combine");
    });
  });

  describe("run --list", () => {
    it("SCENARIO 1 — REQ-LIST-1: 2 available providers → 2 rows numbered 1-2, exit 0", async () => {
      const result = await run(["-l"]);
      expect(result.exitCode).toBe(0);
      // Numbered rows: "1" and "2" appear
      expect(result.stdout).toMatch(/\b1\b/);
      expect(result.stdout).toMatch(/\b2\b/);
      // Provider IDs appear in output
      expect(result.stdout).toContain("openai");
      expect(result.stdout).toContain("anthropic");
    });

    it("SCENARIO 2 — REQ-LIST-2: empty registry → exit 1", async () => {
      // Override registry mock for this specific test
      const { buildDefaultRegistry } = await import("../../../src/adapters/providers/registry.js");
      vi.mocked(buildDefaultRegistry).mockImplementationOnce(() =>
        ({
          list: () => [],
          get: () => undefined,
        }) as any,
      );
      const result = await run(["-l"]);
      expect(result.exitCode).toBe(1);
    });

    it("SCENARIO 3 — REQ-LIST-5: list mode emits zero ANSI escapes (no-color removed)", async () => {
      const result = await run(["-l"]);
      expect(result.exitCode).toBe(0);
      // No ANSI escape sequences (CSI + content + terminal char)
      expect(result.stdout).not.toMatch(/\x1b\[[0-9;]*m/);
    });
  });
});
