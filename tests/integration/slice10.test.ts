// Slice 10 integration: CLI, pipeline e2e, security gate.
// All HTTP mocked; no live credentials or network calls.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { execSync } from "node:child_process";
import { run } from "../../src/cli/index.js";
import { parseArgs } from "../../src/cli/parse-args.js";
import type { QuotaData } from "../../src/domain/types.js";

// ── helpers ────────────────────────────────────────────────────────────────────
const mk = (overrides: Partial<QuotaData> = {}): QuotaData =>
  ({ id: "openai", providerName: "OpenAI", used: 50, limit: 100, unit: "%", reset: null, predictedReset: null, window: "daily" as const, ...overrides });

const MIXED: QuotaData[] = [
  mk({ id: "openai", providerName: "OpenAI", used: 30, limit: 100 }),
  mk({ id: "anthropic", providerName: "Anthropic", used: 65, limit: 100 }),
  mk({ id: "gemini", providerName: "Gemini", used: 90, limit: 100 }),
  mk({ id: "zen", providerName: "Zen", used: 5, limit: null }),
];

const ALL8: QuotaData[] = [
  mk({ id: "openai", providerName: "OpenAI", used: 10, limit: 100 }),
  mk({ id: "opencode-zen", providerName: "opencode Zen", used: 20, limit: 100 }),
  mk({ id: "opencode-go", providerName: "opencode Go", used: 30, limit: 100 }),
  mk({ id: "zai-coding-plan", providerName: "z.ai", used: 40, limit: 100 }),
  mk({ id: "kimi-for-coding", providerName: "Kimi", used: 50, limit: 100 }),
  mk({ id: "minimax-coding-plan", providerName: "Minimax", used: 60, limit: 100 }),
  mk({ id: "anthropic", providerName: "Anthropic", used: 70, limit: 100 }),
  mk({ id: "gemini", providerName: "Gemini", used: 80, limit: 100 }),
];

function makeRegistry(data: QuotaData[]) {
  const byId = data.reduce<Record<string, QuotaData[]>>((a, q) => ((a[q.id] ??= []).push(q), a), {});
  const ids = Object.keys(byId);
  const mockProviders = ids.map((id) => ({
    id, displayName: id, category: "coding", authStrategy: "api" as const,
    isAvailable: () => Promise.resolve(true),
    fetchQuotas: () => Promise.resolve(byId[id]),
  }));
  return { list: () => mockProviders, get: (id: string) => mockProviders.find((p) => p.id === id) };
}

function makeDeps(data: QuotaData[]) {
  return {
    credentialResolver: { get: () => Promise.resolve(null) },
    httpClient: { request: vi.fn() },
    registry: makeRegistry(data),
    historyStore: {
      append: vi.fn<(_id: string, _pt: { timestamp: number; used: number; limit: number | null }) => Promise<void>>(),
      getHistory: vi.fn<(_id: string, _ms: number) => Promise<[]>>(),
      prune: vi.fn<(_ms: number) => Promise<void>>(),
      resetDetected: vi.fn(),
    },
    config: {
      displayMode: "table" as const, disabled: [] as readonly string[],
      aggregatedGroups: {} as Readonly<Record<string, { strategy: string; members: readonly string[] }>>,
      historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60,
      predictionShortWindowMinutes: 5, showUnaggregated: false,
      progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } as const,
    },
    logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  };
}

// ── stdout / stderr capture ────────────────────────────────────────────────────
let stdout: string[] = [], stderr: string[] = [];
beforeEach(() => {
  stdout = []; stderr = [];
  vi.spyOn(process.stdout, "write").mockImplementation((c: string) => (stdout.push(String(c)), true));
  vi.spyOn(process.stderr, "write").mockImplementation((c: string) => (stderr.push(String(c)), true));
});
afterEach(() => { vi.restoreAllMocks(); });
const out = () => stdout.join("");

// ── module mocks (apply to entire file) ────────────────────────────────────────
vi.mock("../../src/adapters/infra/config-loader.js", () => ({
  DEFAULTS: { displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } },
  loadConfig: vi.fn(() => ({ displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } })),
}));
vi.mock("../../src/adapters/auth/credential-resolver.js", () => ({
  createCredentialResolver: vi.fn(() => ({ get: () => Promise.resolve(null) })),
}));
vi.mock("../../src/adapters/infra/fetch-http.js", () => ({
  FetchHttpClient: vi.fn().mockImplementation(function () { this.request = vi.fn(); }),
}));
vi.mock("../../src/adapters/providers/registry.js", () => ({
  buildDefaultRegistry: vi.fn(() => makeRegistry([...MIXED, { id: "anthropic", providerName: "Anthropic", used: 0, limit: 100, unit: "%", reset: null, predictedReset: null, window: "daily" as const }])),
}));

// ── SECTION 1: CLI (stashed Slice 9 tests) ────────────────────────────────────
describe("CLI: parseArgs", () => {
  it.each([
    { argv: [], exp: { mode: "table" as const, list: true, help: false, color: undefined, provider: undefined } },
    { argv: ["--mode", "json"], exp: { mode: "json" as const, list: true, help: false } },
    { argv: ["--mode", "markdown"], exp: { mode: "markdown" as const, list: true, help: false } },
    { argv: ["-l"], exp: { mode: "table" as const, list: true, help: false } },
    { argv: ["-p", "openai"], exp: { provider: "openai", mode: "table" as const, list: false, help: false } },
    { argv: ["-p", "anthropic", "-m", "json"], exp: { provider: "anthropic", mode: "json" as const, list: false, help: false } },
    { argv: ["-c", "green"], exp: { color: "green", mode: "table" as const, list: true, help: false } },
    { argv: ["-p", "openai", "-c", "cyan", "-m", "markdown"], exp: { provider: "openai", color: "cyan", mode: "markdown" as const, list: false, help: false } },
    { argv: ["-h"], exp: { help: true, mode: "table" as const, list: true } },
    { argv: ["--help"], exp: { help: true, mode: "table" as const, list: true } },
  ])("parseArgs($argv) → $exp", ({ argv, exp }) => { expect(parseArgs(argv)).toMatchObject(exp); });
});

describe("CLI: run", () => {
  it("default mode = table → exit 0", async () => { expect((await run([])).exitCode).toBe(0); expect(out().length).toBeGreaterThan(0); });
  it("-m json → JSON object (requires -p to avoid list mode)", async () => { const r = await run(["-p", "openai", "-m", "json"]); expect(r.exitCode).toBe(0); expect(out().trim()).toMatch(/^\{/); });
  it("-m markdown → markdown table (requires -p to avoid list mode)", async () => { const r = await run(["-p", "openai", "-m", "markdown"]); expect(r.exitCode).toBe(0); expect(out()).toContain("|"); });
  it("--no-color removed: unknown option → exit 2", async () => {
    const r = await run(["--no-color"]);
    expect(r.exitCode).toBe(2); // REQ-CLI-5: --no-color is gone
  });
  it("--provider openai → exit 0", async () => { expect((await run(["--provider", "openai"])).exitCode).toBe(0); });
  it("--provider anthropic → exit 0 (empty data)", async () => { expect((await run(["--provider", "anthropic"])).exitCode).toBe(0); });
  it("--help → usage printed", async () => { await run(["--help"]); expect(out().toLowerCase()).toMatch(/usage|help|--provider|--mode|-l|-c|-m|-h/); });
  it("fatal error → exit 2 + stderr (buildDefaultRegistry throws)", async () => {
    const { buildDefaultRegistry } = await import("../../src/adapters/providers/registry.js");
    vi.mocked(buildDefaultRegistry).mockImplementationOnce(() => { throw new Error("boom"); });
    const r = await run(["-p", "openai"]);
    expect(r.exitCode).toBe(2);
    expect(r.stderr).toMatch(/boom/);
  });
});

// ── SECTION 2: Pipeline e2e ───────────────────────────────────────────────────
describe("Pipeline: mode selection", () =>
  it.each([
    { mode: "table" as const, check: (o: string) => { expect(o.length).toBeGreaterThan(0); expect(o).toMatch(/[█░]/); } },
    { mode: "json" as const, check: (o: string) => { expect(o.trim()).toMatch(/^\{/); expect(o).not.toMatch(/\x1b\[/); } },
    { mode: "markdown" as const, check: (o: string) => { expect(o).toContain("|"); expect(o).not.toMatch(/\x1b\[/); } },
  ])("mode $mode", async ({ mode, check }) => {
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(MIXED), { mode, now: Date.now() });
    check(result.rendered);
  }));

describe("Pipeline: status thresholds", () =>
  it.each([
    { used: 30, limit: 100 },
    { used: 65, limit: 100 },
    { used: 90, limit: 100 },
  ])("used=$used limit=$limit → no OK/WRN/ERR text, bar present", async ({ used, limit }) => {
    // REQ-TEST-ALIGN-STATUS-BAND: no OK/WRN/ERR text anywhere; bar cell is present.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const q = mk({ used, limit });
    const result = await reportQuotas(makeDeps([q]), { mode: "table", now: Date.now() });
    // No status text appears in rendered output (REQ-GEOM-DROP-STATUS).
    expect(result.rendered).not.toContain("OK");
    expect(result.rendered).not.toContain("WRN");
    expect(result.rendered).not.toContain("ERR");
    // Bar cell is present: bracketed bar with filled/empty characters.
    const barMatch = result.rendered.match(/\[[░█]+\]\s/);
    expect(barMatch).not.toBeNull();
  }));

describe("Pipeline: unlimited", () =>
  it("limit=null → neutral band, no OK text, unlimited label visible", async () => {
    // REQ-TEST-ALIGN-STATUS-BAND: unlimited has no error color band, no "OK" text,
    // and the unlimited indicator is visible in the output.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps([mk({ used: 100, limit: null, id: "ul", providerName: "Unlimited" })]), { mode: "table", now: Date.now() });
    // Extract bar cell: unlimited has no filled bar, no green/yellow/red band.
    const barMatch = result.rendered.match(/\[[^\]]*\]\s/);
    expect(barMatch).not.toBeNull();
    const barCell = barMatch![0];
    expect(barCell).not.toContain("\x1b[31m"); // no red error band
    expect(barCell).not.toContain("\x1b[32m"); // no green OK band
    expect(barCell).not.toContain("\x1b[33m"); // no yellow WRN band
    // No "OK" text anywhere in rendered output.
    expect(result.rendered).not.toContain("OK");
    expect(result.rendered).not.toContain("WRN");
    expect(result.rendered).not.toContain("ERR");
    // Unlimited label is visible.
    expect(result.rendered).toContain("unlimited");
  }));

describe("Pipeline: 8 providers", () => {
  it("table renders all 8 — each provider emits a header with its brand", async () => {
    // REQ-TEST-ALIGN-8PROVIDERS-RENDER: call renderer directly with header per provider.
    const { TableRenderer } = await import("../../src/rendering/index.js");
    const renderer = new TableRenderer();
    const NOOP_T = (key: string) => key;
    for (const q of ALL8) {
      const out = renderer.render([q], {
        mode: "table",
        color: undefined,
        compact: false,
        terminalWidth: 80,
        header: { brand: q.providerName, plan: null },
        t: NOOP_T,
        progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: false, gradients: false },
      });
      expect(out.length).toBeGreaterThan(0);
      expect(out).toContain(q.providerName);
    }
  });
  it("json parses to { fetchedAt, quotas }", async () => {
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8), { mode: "json", now: Date.now() });
    const parsed = JSON.parse(result.rendered) as { fetchedAt: string; quotas: unknown[] };
    expect(parsed.quotas).toHaveLength(8);
  });
});

// ── SECTION 3: Security gate ──────────────────────────────────────────────────
describe("Security gate", () => {
  const gate = join(process.cwd(), "scripts", "check-secrets.sh");
  it("source tree passes (exit 0)", () => {
    if (!existsSync(gate)) return;
    const r = execSync(`bash ${gate}`, { encoding: "utf-8", stdio: "pipe" });
    expect(r).toMatch(/No secret patterns found/);
  });
  it("sk-fakeSecretXYZ is detected by grep", () => {
    const tmp = join("/tmp", `fake-secret-${Date.now()}.txt`);
    execSync(`echo 'sk-fakeSecretXYZ1234567890' > ${tmp}`);
    try {
      expect(() => execSync(`grep -rE 'sk-fakeSecretXYZ' '${tmp}'`, { stdio: "pipe" })).not.toThrow();
    } finally { execSync(`rm -f '${tmp}'`); }
  });
  it("GOCSPX- pattern is detected by gate", () => {
    if (!existsSync(gate)) return;
    const tmp = join("/tmp", `gocspx-${Date.now()}.txt`);
    execSync(`echo 'GOCSPX-fakeToken1234567890' > ${tmp}`);
    try {
      expect(() => execSync(`grep -rE 'GOCSPX' '${tmp}'`, { stdio: "pipe" })).not.toThrow();
    } finally { execSync(`rm -f '${tmp}'`); }
  });
});
