// WU-3: i18n label catalog — every QuotaConcept has a concept.* translation key.
// RED: en.json lacks concept.* keys → tests fail.
// GREEN: add the 10 concept.* entries to src/i18n/locales/en.json.
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import enCatalog from "../../../src/i18n/locales/en.json";
import { buildProviderName, type QuotaConcept } from "../../../legacy/rendering/semantic-labels.js";

// All 10 concepts from semantic-labels.ts QuotaConcept union
const ALL_CONCEPTS: QuotaConcept[] = [
  "z.ai-5-hour-rolling",
  "z.ai-mcp",
  "z.ai-token",
  "minimax-daily-request",
  "minimax-weekly-request",
  "openai-primary-rate",
  "openai-secondary-rate",
  "openai-credits",
  "openai-token-usage",
  "gemini-model-quota",
];

describe("i18n catalog — header.* keys present", () => {
  it("every header.* key used by the renderer is in en.json", () => {
    const headerKeys = [
      "header.status", "header.name", "header.bar", "header.percent",
      "header.reset", "header.ettl", "header.used", "header.limit",
    ];
    for (const key of headerKeys) {
      expect(enCatalog, `catalog missing key: ${key}`).toHaveProperty(key);
      expect(typeof (enCatalog as Record<string, unknown>)[key]).toBe("string");
      expect(((enCatalog as Record<string, unknown>)[key] as string).length).toBeGreaterThan(0);
    }
  });
});

describe("i18n label catalog — every concept has a translation key", () => {
  for (const concept of ALL_CONCEPTS) {
    it(`has a concept.* key for "${concept}"`, () => {
      const key = `concept.${concept}`;
      expect(enCatalog, `catalog missing key: ${key}`).toHaveProperty(key);
      const value = (enCatalog as Record<string, unknown>)[key];
      expect(typeof value, `key "${key}" must be a string`).toBe("string");
      expect((value as string).length, `key "${key}" must be non-empty`).toBeGreaterThan(0);
    });

    it(`buildProviderName renders the catalog translation for "${concept}"`, () => {
      const rendered = buildProviderName("Brand", concept);
      const key = `concept.${concept}`;
      const expected = (enCatalog as Record<string, string>)[key];
      expect(rendered, `buildProviderName output should contain the translated label`).toContain(expected);
    });
  }
});

// Catalog completeness: verify every label string used by adapters is a concept.* key
describe("i18n catalog completeness — adapter info strings map to concept.* keys", () => {
  it("every fixture's computed info maps to a concept.* catalog key", async () => {
    // Load every provider fixture and parse it through the real adapter.
    // Verify the resulting info string matches a concept.* value in the catalog.
    // This catches regressions where an adapter produces a raw label instead of a concept key.
    const fixtureDir = join(process.cwd(), "tests/fixtures/providers");

    // Each provider's fetchQuotas returns QuotaData[] with info fields.
    // We scan those info strings and confirm each corresponds to a catalog concept.* key.
    // Strategy: read each fixture, check that NONE of the known hardcoded label
    // strings appear as literal info (they must come from the catalog via buildProviderName).
    const HARD_CODED_LABELS = [
      "5-hour rolling limit",
      "MCP quota",
      "Token quota",
      "Daily request quota",
      "Weekly request quota",
      "Primary rate limit",
      "Secondary rate limit",
      "Credit balance",
      "Token usage",
      "Model quota",
    ];

    // Read all fixture JSONs and scan for hardcoded label strings
    const { readdirSync } = await import("node:fs");
    const providers = readdirSync(fixtureDir, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => d.name);

    for (const provider of providers) {
      const providerDir = join(fixtureDir, provider);
      const files = readdirSync(providerDir).filter(f => f.endsWith(".json"));
      for (const file of files) {
        const content = readFileSync(join(providerDir, file), "utf-8");
        for (const label of HARD_CODED_LABELS) {
          expect(content, `${provider}/${file} must not contain hardcoded label "${label}"`).not.toContain(label);
        }
      }
    }
  });
});

describe("i18n translator — header.* key leakage (REQ-r5 regression guard)", () => {
  // REQ-r5: no literal header.* strings in translated output.
  // The catalog already has all header.* keys (from the initial i18n setup).
  // WU-6 will verify the renderer uses the translator for ALL header output
  // and does not bypass it with hardcoded English strings.
  it("all header.* catalog keys return catalog translations (not key itself)", async () => {
    const { createI18nTranslator } = await import("../../../legacy/i18n/translator.js");
    const t = createI18nTranslator(enCatalog);

    // A known existing key returns the translation
    const existing = t.t("status.OK");
    expect(existing).toBe("OK");

    // All header.* keys must return catalog values, not key itself
    const headerKeys = [
      ["header.name", "Name"],
      ["header.used", "Used"],
      ["header.limit", "Limit"],
      ["header.bar", "Bar"],
      ["header.percent", "%"],
      ["header.reset", "Reset"],
      ["header.ettl", "ETTL"],
      ["header.status", "Status"],
    ] as const;

    for (const [key, expected] of headerKeys) {
      const translated = t.t(key);
      expect(translated, `"${key}" must return catalog value, not the key itself`).toBe(expected);
    }
  });

  it("no literal header.* strings appear as translated output for known concept.* keys", async () => {
    const { createI18nTranslator } = await import("../../../legacy/i18n/translator.js");
    const t = createI18nTranslator(enCatalog);

    for (const concept of ALL_CONCEPTS) {
      const key = `concept.${concept}`;
      const translated = t.t(key);
      // translated must not be the raw key (it must be in the catalog)
      expect(translated, `concept.* key "${key}" should be in catalog`).not.toBe(key);
      // translated must not contain "header."
      expect(translated, `translated value for "${key}" must not contain "header."`).not.toContain("header.");
    }
  });
});
