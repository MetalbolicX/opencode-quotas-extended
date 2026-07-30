// Architecture test: every cross-module-consumed .res module must have a .resi file.
// This ensures intentional public API surface and compiler-visible drift detection.
//
// Phase 1 scope: src/domain/*.res + src/testing/DomainFixtures.res
// Phase 2+ will extend coverage to provider and adapter modules.
import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const SRC_DIR = join(import.meta.dirname, "../../src");

// Modules that cross module boundaries (consumed by other modules or act as ports/adapters).
// Internal helpers not listed here should remain private.
const PHASE1_MODULES = [
  // domain modules
  "domain/Types",
  "domain/Aggregation",
  "domain/Prediction",
  "domain/Reset",
  "domain/AggregationDefaults",
  "domain/Domain",
  // testing fixtures (cross-module test surface)
  "testing/DomainFixtures",
];

describe("resi-coverage (phase 1)", () => {
  it.each(PHASE1_MODULES)("%s has a corresponding .resi interface file", (modulePath) => {
    const resPath = join(SRC_DIR, `${modulePath}.res`);
    const resiPath = join(SRC_DIR, `${modulePath}.resi`);

    // The .res file must exist
    expect(existsSync(resPath), `.res file ${resPath} must exist`).toBe(true);

    // The .resi file must also exist
    expect(
      existsSync(resiPath),
      `Interface file ${resiPath} must exist — every cross-module .res needs a .resi`,
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
