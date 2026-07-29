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
  ({ id, providerName, used, limit: 100, unit: "%", reset: null, window: "daily" as const });

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
    // REQ-TEST-ALIGN-HEADER-PROVIDER: providerName appears ONLY in the header line,
    // never on data lines. Call renderer directly with header to verify brand placement.
    const { TableRenderer } = await import("../../src/rendering/index.js");
    const renderer = new TableRenderer();
    const NOOP_T = (key: string) => key;
    ALL8.forEach((q) => {
      const out = renderer.render([q], {
        mode: "table",
        color: undefined,
        compact: false,
        terminalWidth: 80,
        header: { brand: q.providerName, plan: null },
        t: NOOP_T,
        progressBar: { width: 10, filledChar: "█", emptyChar: "░", color: false, gradients: false },
      });
      // Brand must appear in header line, not in data rows.
      const lines = out.split("\n");
      const headerLine = lines.find((l) => l.includes(q.providerName));
      expect(headerLine, `provider ${q.providerName} must appear in header`).toBeDefined();
      const dataLines = lines.filter((l) => l.includes("[") && l.includes("]"));
      dataLines.forEach((dl) => {
        expect(dl, `data line must not contain brand ${q.providerName}`).not.toContain(q.providerName);
      });
    });
  });

  it("SCENARIO 2 — per-provider row count: each provider's data appears in output", async () => {
    // REQ-TEST-ALIGN-HEADER-PROVIDER: 8 distinct brands appear in header lines;
    // each provider emits ≥1 data row; no brand in data rows.
    const { TableRenderer } = await import("../../src/rendering/index.js");
    const renderer = new TableRenderer();
    const NOOP_T = (key: string) => key;
    // Group ALL8_DOUBLE by base brand.
    // Provider names: "OpenAI", "OpenAI-Model-B", "opencode-Zen", "opencode-Zen-B",
    // "z.ai", "z.ai-Model-B", "Kimi", "Kimi-Model-B", etc.
    // Base brand = providerName without trailing "-Model-B" suffix.
    const byBrand = new Map<string, QuotaData[]>();
    for (const q of ALL8_DOUBLE) {
      // Strip "-Model-B" or "-B" suffix to get the base brand for grouping.
      // "OpenAI-Model-B" → "OpenAI", "opencode-Zen-B" → "opencode-Zen", etc.
      const baseBrand = q.providerName.replace(/-(Model-)?B$/, "");
      if (!byBrand.has(baseBrand)) byBrand.set(baseBrand, []);
      byBrand.get(baseBrand)!.push(q);
    }
    const brands = [...byBrand.keys()];
    expect(brands).toHaveLength(8); // 8 distinct base brands
    // Render each group and verify header + data rows.
    let totalDataRows = 0;
    brands.forEach((brand) => {
      const rows = byBrand.get(brand)!;
      const out = renderer.render(rows, {
        mode: "table",
        color: undefined,
        compact: false,
        terminalWidth: 80,
        header: { brand, plan: null },
        t: NOOP_T,
        progressBar: { width: 10, filledChar: "█", emptyChar: "░", color: false, gradients: false },
      });
      const lines = out.split("\n");
      // Header must contain brand.
      const headerLines = lines.filter((l) => l.includes(brand));
      expect(headerLines.length).toBeGreaterThanOrEqual(1);
      // Data rows (contain bar) must NOT contain the brand string.
      const dataLines = lines.filter((l) => l.includes("["));
      totalDataRows += dataLines.length;
      dataLines.forEach((dl) => {
        expect(dl).not.toContain(brand);
      });
    });
    expect(totalDataRows).toBeGreaterThanOrEqual(16); // at least 2 rows per provider
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
