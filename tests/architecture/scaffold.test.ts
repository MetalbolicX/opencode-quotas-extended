import { describe, it, expect, beforeAll } from "vitest";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dirname, "../..");

const EXPECTED_DIRS = [
  "src/domain",
  "src/ports",
  "src/application",
  "src/adapters/auth",
  "src/adapters/infra",
  "src/adapters/providers",
  "src/rendering",
  "src/i18n/locales",
  "src/plugin",
  "src/cli",
  "tests/unit/config",
  "tests/unit/domain",
  "tests/unit/credentials",
  "tests/unit/rendering",
  "tests/unit/providers",
  "tests/characterization",
  "tests/integration",
  "tests/architecture",
  "tests/fixtures/reference",
  "tests/fixtures/providers",
  "commands",
  "schemas",
  "scripts",
] as const;

describe("scaffold", () => {
  describe("directory tree", () => {
    for (const dir of EXPECTED_DIRS) {
      it(`src root directory ${dir} must exist`, () => {
        const fullPath = join(ROOT, dir);
        expect(existsSync(fullPath), `${dir} does not exist`).toBe(true);
      });

      it(`${dir} must be a directory`, () => {
        const fullPath = join(ROOT, dir);
        const stat = require("node:fs").statSync(fullPath);
        expect(stat.isDirectory(), `${dir} is not a directory`).toBe(true);
      });
    }

    it("src directory must contain expected top-level folders", () => {
      const srcPath = join(ROOT, "src");
      const entries = readdirSync(srcPath);
      const expected = [
        "domain",
        "ports",
        "application",
        "adapters",
        "rendering",
        "i18n",
        "plugin",
        "cli",
      ];
      for (const folder of expected) {
        expect(entries, `src/${folder} missing`).toContain(folder);
      }
    });
  });
});
