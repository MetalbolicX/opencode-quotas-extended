// RED → GREEN → REFACTOR: rendering (table/json/markdown/status/bar) + i18n translator.
// All renderers + status thresholds + bar + i18n in ONE consolidated suite.
import { describe, it, expect, beforeAll } from "vitest";
import type { QuotaData } from "../../../src/domain/types.js";
import type { Renderer } from "../../../src/ports/renderer.js";
import type { Translator } from "../../../src/ports/translator.js";

// ── fixtures ─────────────────────────────────────────────────────────────────

const F = {
  openai: { id: "openai", providerName: "OpenAI", used: 75, limit: 100, unit: "%", reset: null, predictedReset: null, window: "daily" as const },
  anthropic: { id: "anthropic", providerName: "Anthropic", used: 45, limit: 50, unit: "req", reset: null, predictedReset: null, window: "daily" as const },
  gemini: { id: "gemini", providerName: "Gemini", used: 120, limit: 100, unit: "req", reset: null, predictedReset: null, window: "monthly" as const },
  unlimited: { id: "zen", providerName: "opencode-zen", used: 99, limit: null, unit: "req", reset: null, predictedReset: null, window: "rolling" as const },
} as const;

const QUOTAS: QuotaData[] = [F.openai, F.anthropic, F.gemini, F.unlimited];

const NOOP_TRANSLATOR: Translator = { t: (k) => k };
const EN_TRANSLATOR: Translator = {
  t: (k) => k === "status.OK" ? "OK" : k === "status.WRN" ? "WRN" : k === "status.ERR" ? "ERR" : k === "status.UNK" ? "UNK" : k === "header.name" ? "Name" : k === "header.used" ? "Used" : k === "header.limit" ? "Limit" : k === "header.bar" ? "Bar" : k === "header.percent" ? "%" : k === "header.reset" ? "Reset" : k === "header.ettl" ? "ETTL" : k === "header.status" ? "Status" : k,
};

// ── dynamic imports resolved in beforeAll ──────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let getStatus!: (used: number, limit: number | null, gradients?: {threshold: number; color: string}[]) => { code: string; ratio: number | null };
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let renderBar!: (ratio: number, opts?: { width?: number; filledChar?: string; emptyChar?: string; color?: boolean }) => string;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let selectRenderer!: (mode: "table" | "json" | "markdown") => Renderer;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let createI18nTranslator!: (catalog: Record<string, string>) => Translator;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let loadCatalog!: (locale: string) => Promise<Record<string, string>>;

beforeAll(async () => {
  const sb = await import("../../../src/rendering/status-bar.js");
  getStatus = sb.getStatus;
  renderBar = sb.renderBar;
  const idx = await import("../../../src/rendering/index.js");
  selectRenderer = idx.selectRenderer;
  const tr = await import("../../../src/i18n/translator.js");
  createI18nTranslator = tr.createI18nTranslator;
  loadCatalog = tr.loadCatalog;
});

// ── status thresholds ──────────────────────────────────────────────────────────

describe("status thresholds", () => {
  it.each([
    { used: 49, limit: 100, expect: "OK" },
    { used: 50, limit: 100, expect: "WRN" },
    { used: 79, limit: 100, expect: "WRN" },
    { used: 80, limit: 100, expect: "ERR" },
    { used: 100, limit: 100, expect: "ERR" },
  ])("ratio $used/$limit → $expect", ({ used, limit, expect: code }) => {
    const s = getStatus(used, limit);
    expect(s.code).toBe(code);
    expect(s.ratio).toBe(used / limit);
  });

  it("unlimited → OK", () => {
    const s = getStatus(9999, null);
    expect(s.code).toBe("OK");
    expect(s.ratio).toBeNull();
  });

  it("custom gradients override defaults", () => {
    // Custom thresholds: green zone < 0.3, yellow [0.3, 0.7), red [0.7, ∞)
    const gs = [{ threshold: 0.3, color: "green" }, { threshold: 0.7, color: "yellow" }, { threshold: 1.0, color: "red" }];
    expect(getStatus(20, 100, gs).code).toBe("OK"); // 0.2 < 0.3 → OK zone
    expect(getStatus(50, 100, gs).code).toBe("WRN"); // 0.5 >= 0.3 && < 0.7
    expect(getStatus(80, 100, gs).code).toBe("ERR"); // 0.8 >= 0.7
  });
});

// ── bar rendering ─────────────────────────────────────────────────────────────

describe("bar rendering", () => {
  it.each([10, 20, 30])("width $w at 70%%", (w) => {
    const bar = renderBar(0.7, { width: w });
    const filled = (bar.match(/█/g) ?? []).length;
    const empty = (bar.match(/░/g) ?? []).length;
    expect(filled + empty).toBe(w);
    expect(filled).toBe(Math.round(0.7 * w));
  });

  it("custom chars", () => {
    const bar = renderBar(0.5, { width: 10, filledChar: "▓", emptyChar: "▒" });
    expect(bar).toContain("▓");
    expect(bar).toContain("▒");
  });

  it("no color strips ANSI", () => {
    const bar = renderBar(0.5, { width: 10, color: false });
    expect(bar).not.toMatch(/\x1b\[\d+m/);
  });
});

// ── renderer factory ─────────────────────────────────────────────────────────

describe("renderer factory", () => {
  it("selects table/json/markdown", () => {
    expect(selectRenderer("table")).toBeDefined();
    expect(selectRenderer("json")).toBeDefined();
    expect(selectRenderer("markdown")).toBeDefined();
  });
});

// ── table renderer ────────────────────────────────────────────────────────────

describe("table renderer", () => {
  it("renders all provider names", () => {
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", t: NOOP_TRANSLATOR });
    expect(out).toContain("OpenAI");
    expect(out).toContain("Anthropic");
    expect(out).toContain("Gemini");
  });

  it("no-color strips ANSI", () => {
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", noColor: true, t: NOOP_TRANSLATOR });
    expect(out).not.toMatch(/\x1b\[\d+m/);
  });
});

// ── json renderer ─────────────────────────────────────────────────────────────

describe("json renderer", () => {
  it("emits valid parseable JSON", () => {
    const r = selectRenderer("json");
    const out = r.render(QUOTAS, { mode: "json", t: NOOP_TRANSLATOR });
    expect(() => JSON.parse(out)).not.toThrow();
  });

  it("never emits ANSI", () => {
    const r = selectRenderer("json");
    const out = r.render(QUOTAS, { mode: "json", t: NOOP_TRANSLATOR });
    expect(out).not.toMatch(/\x1b\[\d+m/);
  });
});

// ── markdown renderer ─────────────────────────────────────────────────────────

describe("markdown renderer", () => {
  it("emits markdown table with pipes", () => {
    const r = selectRenderer("markdown");
    const out = r.render(QUOTAS, { mode: "markdown", t: EN_TRANSLATOR });
    expect(out).toContain("|");
    expect(out).toMatch(/\| *Name *\|/);
  });

  it("never emits ANSI", () => {
    const r = selectRenderer("markdown");
    const out = r.render(QUOTAS, { mode: "markdown", t: NOOP_TRANSLATOR });
    expect(out).not.toMatch(/\x1b\[\d+m/);
  });
});

// ── i18n translator ──────────────────────────────────────────────────────────

describe("i18n translator", () => {
  it("returns key on missing", () => {
    const t = createI18nTranslator({});
    expect(t.t("missing.key")).toBe("missing.key");
  });

  it("interpolates single var", () => {
    const t = createI18nTranslator({ "greeting": "Hello, {name}!" });
    expect(t.t("greeting", { name: "World" })).toBe("Hello, World!");
  });

  it("interpolates multiple vars", () => {
    const t = createI18nTranslator({ "msg": "{greeting}, {name}! You have {n} reqs." });
    expect(t.t("msg", { greeting: "Hi", name: "Alice", n: 42 })).toBe("Hi, Alice! You have 42 reqs.");
  });

  it("loadCatalog loads en locale file", async () => {
    const cat = await loadCatalog("en");
    expect(cat["status.OK"]).toBeDefined();
    expect(typeof cat["status.OK"]).toBe("string");
  });
});
