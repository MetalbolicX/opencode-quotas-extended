// Architecture regression-guard test: type-safety invariants.
// Ensures Obj.magic, %raw, and .resi coverage stay within defined thresholds.
//
// Phase 6 scope: full cross-module coverage + safety guards.
import { describe, it, expect } from "vitest";
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const SRC_DIR = join(import.meta.dirname, "../../src");

// ─── Helpers ────────────────────────────────────────────────────────────────

function walkResFiles(dir: string): string[] {
  const results: string[] = [];
  const entries = readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkResFiles(full));
    } else if (entry.name.endsWith(".res") && !entry.name.endsWith("Tests.res")) {
      results.push(full);
    }
  }
  return results;
}

function countOccurrences(content: string, pattern: string): number {
  const regex = new RegExp(pattern, "g");
  const matches = content.match(regex);
  return matches ? matches.length : 0;
}

// ─── Obj.magic guard ────────────────────────────────────────────────────────

describe("Obj.magic guard", () => {
  it("src/**/*.res (excluding *Tests.res) contains ZERO Obj.magic occurrences", () => {
    const resFiles = walkResFiles(SRC_DIR);
    expect(resFiles.length, "must find .res files").toBeGreaterThan(0);

    let total = 0;
    const violations: string[] = [];
    for (const file of resFiles) {
      const content = readFileSync(file, "utf-8");
      const count = countOccurrences(content, "Obj\\.magic");
      if (count > 0) {
        total += count;
        violations.push(`${file}: ${count}x`);
      }
    }

    expect(
      total,
      `Obj.magic count must be 0. Found ${total} in:\n${violations.join("\n")}`,
    ).toBe(0);
  });
});

// ─── %raw budget ─────────────────────────────────────────────────────────────

describe("%raw budget", () => {
  it("src/**/*.res (excluding *Tests.res) contains at most 12 %raw occurrences", () => {
    const resFiles = walkResFiles(SRC_DIR);
    expect(resFiles.length, "must find .res files").toBeGreaterThan(0);

    let total = 0;
    const details: { file: string; count: number }[] = [];
    for (const file of resFiles) {
      const content = readFileSync(file, "utf-8");
      const count = countOccurrences(content, "%raw");
      if (count > 0) {
        total += count;
        details.push({ file, count });
      }
    }

    expect(
      total,
      `%raw count must be ≤ 12. Found ${total} in:\n${details.map(d => `${d.file}: ${d.count}x`).join("\n")}`,
    ).toBeLessThanOrEqual(12);
  });
});

// ─── .resi coverage ─────────────────────────────────────────────────────────

// Cross-module modules that must each have a matching .resi file.
// Updated to reflect current codebase (Phase 6 completion).
const CROSS_MODULE_MODULES = [
  // domain
  "domain/Types",
  "domain/Aggregation",
  "domain/Prediction",
  "domain/Reset",
  "domain/AggregationDefaults",
  "domain/Domain",
  // testing
  "testing/DomainFixtures",
  // provider port
  "Provider",
  // providers
  "Providers/Registry",
  "Providers/OpenAI",
  "Providers/Zen",
  "Providers/Go",
  "Providers/Zai",
  "Providers/Kimi",
  "Providers/Minimax",
  "Providers/Anthropic",
  "Providers/Gemini",
  // infra
  "Infra/ConfigLoader",
  "Infra/FetchHttp",
  "Infra/JsonFileHistory",
  "Infra/Paths",
  "Infra/Infra",
  // cli
  "Cli/Cli",
  "Cli/ParseArgs",
  "Cli/Messages",
  // rendering
  "rendering/Renderers",
  "rendering/Colors",
  // i18n
  "i18n/Translator",
  // bindings
  "bindings/Node",
  // auth
  "Auth/Auth",
  "Auth/Credential",
  "Auth/CredentialResolver",
];

describe("resi-coverage (full cross-module)", () => {
  it.each(CROSS_MODULE_MODULES)("%s has a corresponding .resi interface file", (modulePath) => {
    const resPath = join(SRC_DIR, `${modulePath}.res`);
    const resiPath = join(SRC_DIR, `${modulePath}.resi`);

    expect(existsSync(resPath), `.res file ${resPath} must exist`).toBe(true);
    expect(
      existsSync(resiPath),
      `Interface file ${resiPath} must exist for cross-module module "${modulePath}"`,
    ).toBe(true);
  });

  it("DomainFixtures.resi exposes all 4 factory functions", () => {
    const resiPath = join(SRC_DIR, "testing/DomainFixtures.resi");
    const content = readFileSync(resiPath, "utf-8");

    const required = [
      "makeQuotaData",
      "makeHistoryPoint",
      "makeQuotaSnapshot",
      "makeAggregationGroup",
    ];

    for (const fn of required) {
      expect(content, `${fn} must be declared in DomainFixtures.resi`).toContain(fn);
    }
  });
});
