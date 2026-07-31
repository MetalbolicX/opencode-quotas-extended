import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

describe("rolldown build config", () => {
  const CONFIG_FILE = join(PROJECT_ROOT, "rolldown.config.ts");
  const PACKAGE_JSON = join(PROJECT_ROOT, "package.json");
  const CLI_ENTRY = join(PROJECT_ROOT, "legacy", "cli", "index.ts");

  it("rolldown.config.ts must exist at the project root", () => {
    expect(existsSync(CONFIG_FILE), "rolldown.config.ts exists at project root").toBe(true);
  });

  it("package.json must invoke rolldown for the build script", () => {
    const pkg = JSON.parse(readFileSync(PACKAGE_JSON, "utf-8")) as {
      scripts: Record<string, string>;
    };
    expect(pkg.scripts.build, "build script uses rolldown").toMatch(/rolldown/);
  });

  it("package.json must not reference bun in scripts or packageManager", () => {
    const pkg = JSON.parse(readFileSync(PACKAGE_JSON, "utf-8")) as {
      scripts: Record<string, string>;
      packageManager?: string;
    };
    const scriptValues = Object.values(pkg.scripts).join(" ");
    expect(scriptValues.toLowerCase(), "no bun scripts").not.toMatch(/\bbun\b/);
    if (pkg.packageManager) {
      expect(pkg.packageManager.toLowerCase(), "no bun packageManager").not.toMatch(/\bbun\b/);
    }
  });

  it("rolldown.config.ts must point at the CLI entry and target Node", () => {
    const content = readFileSync(CONFIG_FILE, "utf-8");
    // ReScript migration: entry is now lib/es6/src/Bootstrap.res.mjs (compiled ReScript bootstrap)
    expect(content, "configures Bootstrap.res.mjs as the entry").toContain("Bootstrap.res.mjs");
    expect(content, "declares node platform").toMatch(/platform:\s*"node"/);
    expect(content, "uses a node shebang banner").toContain("#!/usr/bin/env node");
  });

  it("the CLI entry must exist", () => {
    expect(existsSync(CLI_ENTRY), "src/cli/index.ts exists").toBe(true);
  });
});
