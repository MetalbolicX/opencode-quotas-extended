// RED → GREEN → REFACTOR: rendering (table/json/markdown/status/bar) + i18n translator.
// All renderers + status thresholds + bar + i18n in ONE consolidated suite.
import { describe, it, expect, beforeAll } from "vitest";
import type { QuotaData } from "../../../src/domain/types.js";
import type { Renderer } from "../../../src/ports/renderer.js";
import type { Translator } from "../../../src/ports/translator.js";

// ── fixtures ─────────────────────────────────────────────────────────────────

const F = {
  openai: { id: "openai", providerName: "OpenAI", used: 75, limit: 100, unit: "%", reset: null, window: "daily" as const, info: "OpenAI" },
  anthropic: { id: "anthropic", providerName: "Anthropic", used: 45, limit: 50, unit: "req", reset: null, window: "daily" as const, info: "Anthropic" },
  gemini: { id: "gemini", providerName: "Gemini", used: 120, limit: 100, unit: "req", reset: null, window: "monthly" as const, info: "Gemini" },
  unlimited: { id: "zen", providerName: "opencode-zen", used: 99, limit: null, unit: "req", reset: null, window: "rolling" as const, info: "opencode-zen" },
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
let renderBar!: (ratio: number, opts?: { width?: number; filledChar?: string; emptyChar?: string; colorName?: string; framed?: boolean; colorSplit?: "filled" | "none" }) => string;
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
    const empty = (bar.match(/\./g) ?? []).length;
    expect(filled + empty).toBe(w);
    expect(filled).toBe(Math.round(0.7 * w));
  });

  it("custom chars", () => {
    const bar = renderBar(0.5, { width: 10, filledChar: "▓", emptyChar: "▒" });
    expect(bar).toContain("▓");
    expect(bar).toContain("▒");
  });

  it("no colorName → plain bar, no ANSI codes", () => {
    const bar = renderBar(0.5, { width: 10 });
    expect(bar).not.toMatch(/\x1b\[\d+m/);
    expect(bar).toMatch(/^[█.]+$/);
  });

  it("colorName green → bar wrapped in green ANSI", () => {
    const bar = renderBar(0.5, { width: 10, colorName: "green" });
    // Green SGR open (\x1b[32m) and reset (\x1b[0m)
    expect(bar).toMatch(/\x1b\[32m/);
    expect(bar).toMatch(/\x1b\[0m/);
    expect(bar).toContain("█");
    expect(bar).toContain(".");
  });

  it("colorName yellow → bar wrapped in yellow ANSI", () => {
    const bar = renderBar(0.5, { width: 10, colorName: "yellow" });
    expect(bar).toMatch(/\x1b\[33m/);
    expect(bar).toMatch(/\x1b\[0m/);
  });

  it("colorName brightRed → bar wrapped in bright-red ANSI", () => {
    const bar = renderBar(0.5, { width: 10, colorName: "brightRed" });
    expect(bar).toMatch(/\x1b\[91m/);
    expect(bar).toMatch(/\x1b\[0m/);
  });

  it("colorName is STATIC — 0.9 ratio with green is GREEN, not red", () => {
    // Static color means the color comes from the NAME, not the ratio.
    // A bar at 0.9 with colorName="green" must be green, not red.
    const bar = renderBar(0.9, { width: 10, colorName: "green" });
    expect(bar).toMatch(/\x1b\[32m/);  // green, NOT red (31)
    expect(bar).not.toMatch(/\x1b\[31m/); // no red
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

  it("color=undefined strips ANSI (plain bars)", () => {
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", color: undefined, t: NOOP_TRANSLATOR });
    expect(out).not.toMatch(/\x1b\[\d+m/);
  });

  it("color=green produces green-wrapped bars", () => {
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", color: "green", t: NOOP_TRANSLATOR });
    // All bars should be wrapped in green ANSI
    expect(out).toMatch(/\x1b\[32m/);
    expect(out).toMatch(/\x1b\[0m/);
    expect(out).toContain("OpenAI");
    expect(out).toContain("Anthropic");
    expect(out).toContain("Gemini");
  });
});

// ── compact table renderer ─────────────────────────────────────────────────────

describe("table renderer — compact mode", () => {
  it("compact=true omits reset and ettl columns", () => {
    // compact layout drops the two time-based columns to fit footer width.
    // The six-column full table (status/name/bar/percent/reset/ettl) becomes
    // four-column (status/name/bar/percent) in compact mode.
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", compact: true, t: EN_TRANSLATOR });
    // These column headers must NOT appear in compact output
    expect(out).not.toContain("Reset");
    expect(out).not.toContain("ETTL");
    // But name, bar, and percent must still be present
    expect(out).toContain("OpenAI");
    expect(out).toMatch(/[█░]/); // bar chars
    expect(out).toMatch(/%/);    // percent
  });

  it("compact=false (full) retains the framed layout with semantic labels and reset context", () => {
    // The mmx-style renderer (REQ-r3 + REQ-r4) does not use legacy "Reset"/"ETTL" column
    // headers — reset context is rendered inline per row (e.g. "in 5h"). The frame MUST
    // still wrap the rows. Prediction/ETTL was removed from QuotaData because no
    // implementation wires it; the cell renders as "—" for non-compact mode.
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", compact: false, t: EN_TRANSLATOR });
    expect(out).toMatch(/^\+-+\+$/m);                // top frame border
    expect(out).toMatch(/\+-+\+$/m);                 // bottom frame border
    expect(out).toMatch(/[█.]/);                     // bar chars present
    expect(out).not.toContain("Reset");              // legacy column header removed
    expect(out).not.toContain("ETTL");               // legacy column header removed
  });

  it("both compact and full contain bar characters (█ or ░)", () => {
    // The progress bar is the primary visual signal and appears regardless of column count.
    const r = selectRenderer("table");
    const fullOut = r.render(QUOTAS, { mode: "table", compact: false, t: EN_TRANSLATOR });
    const compactOut = r.render(QUOTAS, { mode: "table", compact: true, t: EN_TRANSLATOR });
    expect(fullOut).toMatch(/[█░]/);
    expect(compactOut).toMatch(/[█░]/);
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

// ── renderBar — framed option ─────────────────────────────────────────────────

describe("renderBar — framed option", () => {
  it("returns bare bar when framed=false", () => {
    const bar = renderBar(0.4);
    // backward compat: bare bar (10 wide default, █ and .)
    expect(bar).toMatch(/^[█.]+$/);
    expect(bar).not.toContain("[");
    expect(bar).not.toContain("]");
  });

  it("returns bracketed bar with trailing space when framed=true", () => {
    // Default width is 10 (REQ-r2): ratio 0.4 → 4 filled + 6 empty.
    expect(renderBar(0.4, { framed: true })).toBe("[████......] ");
  });

  it("uses . as default empty char when framed", () => {
    expect(renderBar(0.4, { framed: true })).toContain(".");
  });

  it("clamps ratio to [0,1]", () => {
    expect(renderBar(-0.1, { framed: true })).toBe("[..........] ");
    expect(renderBar(1.5, { framed: true })).toBe("[██████████] ");
  });

  it("framed=true with width=10", () => {
    expect(renderBar(0.5, { framed: true, width: 10 })).toBe("[█████.....] ");
  });
});

// ── renderBar — colorSplit=filled ────────────────────────────────────────────

describe("renderBar — colorSplit=filled", () => {
  it("wraps filled portion in colorName and empty in dim", () => {
    // With width=10 (new default) and ratio=0.4: 4 filled + 6 empty
    const out = renderBar(0.4, { framed: true, colorName: "green", colorSplit: "filled" });
    // Filled = "████" wrapped in green, empty = "......" wrapped in dim
    expect(out).toContain("\x1b[32m████\x1b[0m");
    expect(out).toContain("\x1b[2m......\x1b[0m");
  });

  it("colorSplit=filled without colorName falls back to plain bar", () => {
    const out = renderBar(0.5, { colorSplit: "filled" });
    expect(out).not.toMatch(/\x1b\[\d+m/);
  });

  it("colorSplit=none (default) emits no ANSI", () => {
    const out = renderBar(0.5, { colorSplit: "none" });
    expect(out).not.toMatch(/\x1b\[\d+m/);
  });
});

// ── TableRenderer — unit-aware formatting ─────────────────────────────────────

describe("TableRenderer — unit-aware formatting", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let TableRenderer!: new () => any;

  beforeAll(async () => {
    const mod = await import("../../../src/rendering/index.js");
    TableRenderer = mod.TableRenderer;
  });

  const pctRow: QuotaData = {
    id: "x", providerName: "z.ai · 5h quota",
    used: 12, limit: 100, unit: "%",
    reset: new Date(Date.now() + 7 * 3600 * 1000),
    window: "rolling-5h",
    info: "5h quota",
  };

  it("renders percentage rows with bar + 'X% used'", () => {
    const out = new TableRenderer().render([pctRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out).toContain("[█");
    expect(out).toMatch(/12%\s*used/);
    // Data row uses info (clipped), not providerName; header carries brand/plan
    expect(out).toContain("5h quota");
  });

  const tokenRow: QuotaData = {
    id: "x", providerName: "OpenAI · Token usage",
    used: 2_400_000, limit: 10_000_000, unit: "tokens",
    reset: null, window: "rolling",
    info: "Token usage",
  };

  it("renders token rows as text-only (no bar), humanized numbers", () => {
    const out = new TableRenderer().render([tokenRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out).not.toContain("[");
    expect(out).toContain("tokens");
    expect(out).toMatch(/2\.4M\s*\/\s*10M\s*tokens/);
  });

  const creditRow: QuotaData = {
    id: "x", providerName: "OpenAI · Credit balance",
    used: 12.5, limit: null, unit: "credits",
    reset: null, window: "rolling",
    info: "Credit balance",
  };

  it("renders credits as 'balance: X'", () => {
    const out = new TableRenderer().render([creditRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out).toContain("balance");
    expect(out).toContain("12.5");
  });

  const unlimitedRow: QuotaData = {
    id: "x", providerName: "Anthropic · Token usage",
    used: 100, limit: null, unit: "tokens",
    reset: null, window: "daily",
    info: "Token usage",
  };

  it("renders unlimited as 'no limit'", () => {
    const out = new TableRenderer().render([unlimitedRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out).toContain("no limit");
  });

  const reqRow: QuotaData = {
    id: "x", providerName: "Minimax · Daily request quota",
    used: 850, limit: 1000, unit: "requests",
    reset: null, window: "daily",
    info: "Daily request quota",
  };

  it("renders requests as 'used / limit requests'", () => {
    const out = new TableRenderer().render([reqRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out).toMatch(/850\s*\/\s*1000\s*requests/);
  });

  it("renders unlimited requests as 'no limit'", () => {
    const unlimitedReq: QuotaData = {
      id: "y", providerName: "Zen · Requests",
      used: 50, limit: null, unit: "requests",
      reset: null, window: "rolling",
      info: "Requests",
    };
    const out = new TableRenderer().render([unlimitedReq], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out).toContain("no limit");
  });
});

// ── TableRenderer — ASCII frame ───────────────────────────────────────────────

describe("TableRenderer — ASCII frame", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let TableRenderer!: new () => any;

  beforeAll(async () => {
    const mod = await import("../../../src/rendering/index.js");
    TableRenderer = mod.TableRenderer;
  });

  const sampleRow: QuotaData = {
    id: "z-1", providerName: "z.ai · 5h quota",
    used: 12, limit: 100, unit: "%",
    reset: null, window: "rolling-5h",
    info: "5h quota",
  };

  it("wraps rows in +---+ / | | frame", () => {
    const out = new TableRenderer().render([sampleRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    expect(out.split("\n")[0]).toMatch(/^\+-+\+$/);
    expect(out.split("\n").at(-1)).toMatch(/^\+-+\+$/);
  });

  it("includes branded header row with provider name", () => {
    const out = new TableRenderer().render([sampleRow], {
      terminalWidth: 80,
      t: NOOP_TRANSLATOR,
      header: { brand: "z.ai", plan: "Coding Plan" },
    });
    expect(out).toContain("z.ai");
    expect(out).toContain("Coding Plan");
  });

  it("clamps terminalWidth to [60,80]", () => {
    const dummy: QuotaData = {
      id: "d", providerName: "X",
      used: 1, limit: 10, unit: "%",
      reset: null, window: "daily",
    };
    const narrow = new TableRenderer().render([dummy], { terminalWidth: 30, t: NOOP_TRANSLATOR });
    const wide = new TableRenderer().render([dummy], { terminalWidth: 200, t: NOOP_TRANSLATOR });
    // Frame top line length is width + 2 (for + and +)
    expect(narrow.split("\n")[0].length).toBe(62); // 60 inner + 2 corners
    expect(wide.split("\n")[0].length).toBe(82);   // 80 inner + 2 corners
  });

  it("body rows are enclosed in | |", () => {
    const out = new TableRenderer().render([sampleRow], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    const lines = out.split("\n");
    // skip top (+---+) and header (| brand |) — body rows start at index 2
    for (let i = 2; i < lines.length - 1; i++) {
      expect(lines[i]).toMatch(/^\| .+ \|$/);
    }
  });
});

// ── REQ-r5 regression: no literal header.* leakage ─────────────────────────────

describe("renderer — no literal header.* leakage (REQ-r5)", () => {
  it("table output never contains 'header.' strings", () => {
    const r = selectRenderer("table");
    const out = r.render(QUOTAS, { mode: "table", t: EN_TRANSLATOR });
    expect(out).not.toMatch(/header\./);
  });

  it("JSON output never contains 'header.' strings", () => {
    const r = selectRenderer("json");
    const out = r.render(QUOTAS, { mode: "json", t: EN_TRANSLATOR });
    expect(out).not.toMatch(/header\./);
  });

  it("markdown output never contains 'header.' strings", () => {
    const r = selectRenderer("markdown");
    const out = r.render(QUOTAS, { mode: "markdown", t: EN_TRANSLATOR });
    expect(out).not.toMatch(/header\./);
  });
});

// ── PR1: stable geometry — REQ-GEOM-NO-OVERFLOW ──────────────────────────────

describe("table renderer — stable geometry (PR1)", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let TableRenderer!: new () => any;

  beforeAll(async () => {
    const mod = await import("../../../src/rendering/index.js");
    TableRenderer = mod.TableRenderer;
  });

  it("28-char providerName → body width equals 6-char provider case", () => {
    const short: QuotaData = {
      id: "s", providerName: "OpenAI", used: 50, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const long: QuotaData = {
      id: "l", providerName: "Minimax · Daily request quota", used: 50, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const shortOut = new TableRenderer().render([short], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    const longOut = new TableRenderer().render([long], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    const shortBody = shortOut.split("\n").find(l => l.includes("50%"))!;
    const longBody = longOut.split("\n").find(l => l.includes("50%"))!;
    expect(longBody.length).toBe(shortBody.length);
  });

  it("40-char providerName → body width equals 28-char case", () => {
    const a: QuotaData = {
      id: "a", providerName: "Minimax · Daily request quota", used: 50, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const b: QuotaData = {
      id: "b", providerName: "ProviderNameWithExactlyFortyCharactersLong!!", used: 50, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const aOut = new TableRenderer().render([a], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    const bOut = new TableRenderer().render([b], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    const aBody = aOut.split("\n").find(l => l.includes("50%"))!;
    const bBody = bOut.split("\n").find(l => l.includes("50%"))!;
    expect(bBody.length).toBe(aBody.length);
  });
});

// ── PR1: provider identity — REQ-GEOM-DROP-PROVIDER-COL ──────────────────────

describe("table renderer — provider identity header-only (PR1)", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let TableRenderer!: new () => any;

  beforeAll(async () => {
    const mod = await import("../../../src/rendering/index.js");
    TableRenderer = mod.TableRenderer;
  });

  it("providerName absent from data rows but present in header", () => {
    const row: QuotaData = {
      id: "x", providerName: "z.ai · 5-hour rolling limit", used: 12, limit: 100, unit: "%",
      reset: null, window: "rolling-5h",
    };
    const out = new TableRenderer().render([row], {
      terminalWidth: 80,
      t: NOOP_TRANSLATOR,
      header: { brand: "z.ai", plan: "Coding Plan" },
    });
    // Header should contain the brand
    expect(out).toContain("z.ai");
    // But data row (not header line) should NOT contain the full branded name
    const lines = out.split("\n");
    const dataLine = lines.find(l => l.includes("12%"))!;
    expect(dataLine).not.toContain("z.ai · 5-hour rolling limit");
  });

  it("multiple providers — only one header row each, no provider column in data rows", () => {
    const rows: QuotaData[] = [
      { id: "a", providerName: "Provider A · First concept", used: 10, limit: 100, unit: "%", reset: null, window: "daily" },
      { id: "b", providerName: "Provider B · Second concept", used: 20, limit: 100, unit: "%", reset: null, window: "daily" },
    ];
    const out = new TableRenderer().render(rows, { terminalWidth: 80, t: NOOP_TRANSLATOR });
    const lines = out.split("\n");
    // Count lines that contain the branded name pattern
    const brandedLines = lines.filter(l => l.includes("Provider A") || l.includes("Provider B"));
    // Should be at most 1 header line each, not in every data row
    expect(brandedLines.length).toBeLessThanOrEqual(2);
  });
});

// ── PR1: status — REQ-GEOM-DROP-STATUS ───────────────────────────────────────

describe("table renderer — no status column (PR1)", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let TableRenderer!: new () => any;

  beforeAll(async () => {
    const mod = await import("../../../src/rendering/index.js");
    TableRenderer = mod.TableRenderer;
  });

  it("percentage rows have no separate status cell", () => {
    const row: QuotaData = {
      id: "x", providerName: "Test", used: 60, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const out = new TableRenderer().render([row], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    // Status text OK/WRN/ERR must not appear as standalone text in the row
    expect(out).not.toMatch(/\bOK\b/);
    expect(out).not.toMatch(/\bWRN\b/);
    expect(out).not.toMatch(/\bERR\b/);
  });

  it("non-token rows show no inline status glyph", () => {
    const row: QuotaData = {
      id: "x", providerName: "Test", used: 85, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const out = new TableRenderer().render([row], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    // No ✓ / ! / ✕ / ? glyphs in non-token rows
    expect(out).not.toContain("✓");
    expect(out).not.toContain("!");
    expect(out).not.toContain("✕");
    expect(out).not.toContain("?");
  });
});

// ── PR1: token rows — REQ-GEOM-TOKEN-ROW-EXCEPTION ───────────────────────────

describe("table renderer — token row inline glyph (PR1)", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let TableRenderer!: new () => any;

  beforeAll(async () => {
    const mod = await import("../../../src/rendering/index.js");
    TableRenderer = mod.TableRenderer;
  });

  it("token row shows inline status glyph and no bar", () => {
    const row: QuotaData = {
      id: "x", providerName: "OpenAI · Token usage", used: 12000, limit: 50000, unit: "tokens",
      reset: null, window: "rolling",
    };
    const out = new TableRenderer().render([row], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    // Must show humanized token numbers
    expect(out).toMatch(/12K\s*\/\s*50K\s*tokens/);
    // No [ bar brackets for token rows
    expect(out).not.toContain("[");
    expect(out).not.toContain("]");
    // Must show one of the status glyphs
    const hasGlyph = out.includes("✓") || out.includes("!") || out.includes("✕") || out.includes("?");
    expect(hasGlyph).toBe(true);
  });

  it("non-token row never shows status glyph", () => {
    const row: QuotaData = {
      id: "x", providerName: "OpenAI", used: 75, limit: 100, unit: "%",
      reset: null, window: "daily",
    };
    const out = new TableRenderer().render([row], { terminalWidth: 80, t: NOOP_TRANSLATOR });
    // No glyphs in percent rows (bar conveys status)
    expect(out).not.toContain("✓");
    expect(out).not.toContain("✕");
  });
});
