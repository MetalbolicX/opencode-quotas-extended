import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

describe("build script", () => {
  const BUILD_SCRIPT = join(PROJECT_ROOT, "scripts/build.ts");

  it("scripts/build.ts must exist", () => {
    expect(existsSync(BUILD_SCRIPT), "build script exists").toBe(true);
  });

  it("scripts/build.ts must be executable (shebang or runnable)", () => {
    const content = readFileSync(BUILD_SCRIPT, "utf-8");
    // Must have a shebang or be a runnable Node script
    expect(
      content.startsWith("#!") || content.includes("import"),
      "build script must be a runnable script"
    ).toBe(true);
  });

  it("scripts/build.ts must clean dist before building", () => {
    const content = readFileSync(BUILD_SCRIPT, "utf-8");
    expect(content.toLowerCase(), "build script must remove dist directory").toMatch(/rm.*dist|remove.*dist|clean.*dist/i);
  });

  it("scripts/build.ts must invoke tsc or bun build", () => {
    const content = readFileSync(BUILD_SCRIPT, "utf-8");
    expect(content, "build script must invoke tsc or bun build").toMatch(/tsc|bun build|bun\s+build/i);
  });
});
