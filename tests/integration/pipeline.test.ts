// Slice 13 — 8-provider integration test + per-provider row count.
// RED: tests written first, referencing production behavior.
// why: proves the plugin's stated scope (8 providers) end-to-end.
// how: each provider is independently mocked to return 1+ QuotaData
//      entries; the pipeline aggregates and renders them all.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { QuotaData } from "../../src/domain/types.js";

// ── helpers ────────────────────────────────────────────────────────────────────

/** Make a minimal QuotaData entry for a given provider. */
const mk = (id: string, providerName: string, used = 10): QuotaData =>
  ({ id, providerName, used, limit: 100, unit: "%", reset: null, predictedReset: null, window: "daily" as const });

// All 8 providers each return exactly 1 row.
const ALL8: QuotaData[] = [
  mk("openai",              "OpenAI"),
  mk("zen",                 "opencode Zen"),
  mk("go",                  "opencode Go"),
  mk("zai",                 "z.ai"),
  mk("kimi",                "Kimi"),
  mk("minimax",             "Minimax"),
  mk("anthropic",           "Anthropic"),
  mk("gemini",               "Gemini"),
];

// Per-provider dataset: each provider returns 2 rows with DISTINCT providerNames
// so each row is individually identifiable in the table renderer (which uses providerName
// as the name column — duplicate names would only appear once, making row-count
// assertions ambiguous). Distinct names let us verify all 16 rows appear individually.
const ALL8_DOUBLE: QuotaData[] = [
  mk("openai",              "OpenAI",              10),
  mk("openai-model-b",      "OpenAI-Model-B",      20),
  mk("zen",                 "opencode-Zen",        15),
  mk("zen-model-b",         "opencode-Zen-B",      25),
  mk("go",                  "opencode-Go",         30),
  mk("go-model-b",          "opencode-Go-B",       40),
  mk("zai",                 "z.ai",                35),
  mk("zai-model-b",         "z.ai-Model-B",        45),
  mk("kimi",                "Kimi",                50),
  mk("kimi-model-b",        "Kimi-Model-B",        60),
  mk("minimax",             "Minimax",              55),
  mk("minimax-model-b",     "Minimax-Model-B",     65),
  mk("anthropic",           "Anthropic",            70),
  mk("anthropic-model-b",   "Anthropic-Model-B",   80),
  mk("gemini",              "Gemini",               85),
  mk("gemini-model-b",      "Gemini-Model-B",       95),
];

/** Build a mock registry from an array of QuotaData. */
function makeRegistry(data: QuotaData[]) {
  const byId = data.reduce<Record<string, QuotaData[]>>((a, q) => ((a[q.id] ??= []).push(q), a), {});
  const ids  = Object.keys(byId);
  const mockProviders = ids.map((id) => ({
    id,
    displayName: id,
    category:    "coding",
    authStrategy: "api" as const,
    isAvailable:  () => Promise.resolve(true),
    fetchQuotas:  () => Promise.resolve(byId[id]),
  }));
  return {
    list: () => mockProviders,
    get:  (id: string) => mockProviders.find((p) => p.id === id),
  };
}

/** Build full ReportDeps for the pipeline. */
function makeDeps(data: QuotaData[]) {
  return {
    credentialResolver: { get: () => Promise.resolve(null) },
    httpClient:        { request: vi.fn() },
    registry:          makeRegistry(data),
    historyStore: {
      append:        vi.fn<(_id: string, _pt: { timestamp: number; used: number; limit: number | null }) => Promise<void>>(),
      getHistory:    vi.fn<(_id: string, _ms: number) => Promise<[]>>(),
      prune:         vi.fn<(_ms: number) => Promise<void>>(),
      resetDetected: vi.fn(),
    },
    config: {
      displayMode:            "table" as const,
      disabled:               [] as readonly string[],
      aggregatedGroups:       {} as Readonly<Record<string, { strategy: string; members: readonly string[] }>>,
      historyMaxAgeHours:     24,
      pollingInterval:        0,
      predictionWindowMinutes: 60,
      predictionShortWindowMinutes: 5,
      showUnaggregated:       false,
      progressBar: {
        width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false,
      } as const,
    },
    logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  };
}

// ── stdout capture ──────────────────────────────────────────────────────────────
let stdout: string[] = [], stderr: string[] = [];
beforeEach(() => {
  stdout = []; stderr = [];
  vi.spyOn(process.stdout, "write").mockImplementation((c: string) => (stdout.push(String(c)), true));
  vi.spyOn(process.stderr, "write").mockImplementation((c: string) => (stderr.push(String(c)), true));
});
afterEach(() => { vi.restoreAllMocks(); });

// ── RED acceptance scenarios ────────────────────────────────────────────────────

describe("8-provider pipeline (integration)", () => {

  it("SCENARIO 1 — all 8 providers mocked → pipeline renders 8 rows", async () => {
    // RED: reportQuotas is called with a registry containing 8 providers,
    // each returning 1 QuotaData entry. The renderer must show all 8 provider names.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8), { mode: "table", now: Date.now() });
    expect(result.rendered.length).toBeGreaterThan(0);
    ALL8.forEach((q) => {
      expect(result.rendered).toContain(q.providerName);
    });
  });

  it("SCENARIO 2 — per-provider row count: each provider's data appears in output", async () => {
    // RED: when each provider returns 2 rows with distinct providerNames,
    // the table renderer shows all 16 rows with their respective providerName values.
    // The table's name column displays providerName, not id.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8_DOUBLE), { mode: "table", now: Date.now() });
    // Every unique providerName must appear in the rendered table.
    const uniqueProviders = [...new Set(ALL8_DOUBLE.map((q) => q.providerName))];
    expect(uniqueProviders).toHaveLength(16); // 8 providers × 2 rows = 16 distinct names
    uniqueProviders.forEach((name) => {
      expect(result.rendered, `providerName=${name} must appear in rendered table`).toContain(name);
    });
    // Verify the row count: the mmx-style frame is frame-top (with brand inside) + 16 data rows + frame-bottom = 18 lines.
    const lines = result.rendered.trim().split("\n");
    expect(lines).toHaveLength(18); // frame-top + 16 data rows + frame-bottom
  });

  it("SCENARIO 3 — registry.size === 8 (all 8 providers registered)", async () => {
    // RED: buildDefaultRegistry must produce a registry with exactly 8 entries.
    // This is asserted by counting the list() output.
    const { buildDefaultRegistry } = await import("../../src/adapters/providers/registry.js");
    const fakeCred = { get: async () => null } as any;
    const fakeHttp = { request: vi.fn() } as any;
    const r = buildDefaultRegistry(fakeCred, fakeHttp);
    expect(r.list()).toHaveLength(8);
  });

  it("SCENARIO 4 — each of the 8 provider IDs is present in the registry", async () => {
    // RED: get() returns a provider for each of the canonical 8 IDs.
    const { buildDefaultRegistry } = await import("../../src/adapters/providers/registry.js");
    const fakeCred = { get: async () => null } as any;
    const fakeHttp = { request: vi.fn() } as any;
    const r = buildDefaultRegistry(fakeCred, fakeHttp);
    const EXPECTED_IDS = ["anthropic", "gemini", "go", "kimi", "minimax", "openai", "zai", "zen"];
    for (const id of EXPECTED_IDS) {
      const p = r.get(id);
      expect(p, `provider ${id} must be registered`).toBeDefined();
      expect(p!.id).toBe(id);
    }
  });

  it("SCENARIO 5 — JSON mode: 8-provider data parses to array with 8 entries", async () => {
    // RED: when in JSON mode, the output must be parseable and contain 8 quota objects.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8), { mode: "json", now: Date.now() });
    const parsed = JSON.parse(result.rendered) as { fetchedAt: string; quotas: unknown[] };
    expect(parsed.quotas).toHaveLength(8);
  });

  it("SCENARIO 6 — markdown mode: 8 providers render as a markdown table", async () => {
    // RED: markdown renderer produces a table with pipe characters and all 8 names.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8), { mode: "markdown", now: Date.now() });
    expect(result.rendered).toContain("|");
    ALL8.forEach((q) => { expect(result.rendered).toContain(q.providerName); });
  });

  // ── WU-7: i18n catalog must be loaded so renderer never prints literal header.* strings ─

  it("SCENARIO 7 — pipeline loads i18n catalog: markdown output has no literal 'header.*' keys", async () => {
    // RED: when pipeline passes a real (non-empty) translator, MarkdownRenderer must NOT emit
    // literal "header.name", "header.status", "header.percent", "header.reset", "header.ettl".
    // The fix: report-pipeline.ts must call loadCatalog("en") and pass the catalog to createI18nTranslator.
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8), { mode: "markdown", now: Date.now() });
    // Pipeline must not leak literal i18n key names — this was the WU-6 regression.
    expect(result.rendered).not.toMatch(/header\./);
    // The translated header "Name" (from header.name catalog key) SHOULD appear as the column header.
    // This assertion verifies the catalog was loaded: "Name" is the translation, not the key.
    expect(result.rendered).toMatch(/^\s*\|\s*Name\s*\|/m);
  });

  it("SCENARIO 8 — pipeline loads i18n catalog: JSON mode has no header.* keys", async () => {
    // RED: JSON renderer doesn't use translator keys, but the pipeline should still
    // load the catalog correctly (no crashes, no literal header.* in any intermediate output).
    const { reportQuotas } = await import("../../src/application/report-pipeline.js");
    const result = await reportQuotas(makeDeps(ALL8), { mode: "json", now: Date.now() });
    expect(result.rendered).not.toMatch(/header\./);
  });

});
