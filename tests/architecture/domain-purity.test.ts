// Structural test: domain modules must have zero I/O imports.
// This test reads source files and asserts forbidden patterns are absent.

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const DOMAIN_DIR = join(import.meta.dirname, "../../src/domain");
const FORBIDDEN = [
  "node:fs", "node:path", "node:net", "node:http", "node:https",
  "node:perf_hooks", "fetch(", " cross-fetch", "node-fetch",
  "src/ports", "src/adapters", "src/services", "src/cli", "src/plugin",
];

describe("domain-purity", () => {
  const domainFiles = ["aggregation.ts", "prediction.ts", "reset.ts", "index.ts", "types.ts"];

  it.each(domainFiles)("%s has no I/O imports", (file) => {
    const src = readFileSync(join(DOMAIN_DIR, file), "utf-8");
    for (const pat of FORBIDDEN) {
      expect(src, `found forbidden: ${pat}`).not.toContain(pat);
    }
  });
});
