import { describe, it } from "vitest";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";
import { tmpdir } from "node:os";
import { mkdtempSync } from "node:fs";

const projectRoot = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const cli = join(projectRoot, "dist", "cli", "index.js");

describe("CLI entrypoint", () => {
  it("runs when invoked through a relative path (npx shim case)", () => {
    const tmpDir = mkdtempSync(join(tmpdir(), "opencode-quotas-"));
    const relPath = relative(tmpDir, cli);

    const result = spawnSync(process.execPath, [relPath, "--help"], {
      cwd: tmpDir,
      env: { ...process.env, NODE_NO_WARNINGS: "1" },
      encoding: "utf8",
    });

    expect(result.status).toBe(0);
    expect(result.stdout).toMatch(/Usage:|--help|--list/i);
    expect(result.stdout.length).toBeGreaterThan(0);
  });
});
