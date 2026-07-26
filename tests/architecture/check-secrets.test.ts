import { describe, it, expect } from "vitest";
import { existsSync, writeFileSync, unlinkSync } from "node:fs";
import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SCRIPT = join(PROJECT_ROOT, "scripts/check-secrets.sh");
const FAKE_SECRET_FILE = join(PROJECT_ROOT, "src/fake-secret-test.ts");

function runScript(): Promise<{ code: number; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [SCRIPT], { cwd: PROJECT_ROOT });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d) => (stdout += d.toString()));
    child.stderr?.on("data", (d) => (stderr += d.toString()));
    child.on("close", (code) => resolve({ code: code ?? 0, stdout, stderr }));
  });
}

describe("check-secrets.sh", () => {
  it("script must exist and be executable", () => {
    expect(existsSync(SCRIPT), "check-secrets.sh exists").toBe(true);
  });

  it("exits 0 when no secrets are present in src/", async () => {
    // Ensure clean state — remove fake file if it exists from a previous run
    try { unlinkSync(FAKE_SECRET_FILE); } catch { /* ok */ }
    const { code, stdout } = await runScript();
    expect(code, `expected exit 0. stdout: ${stdout}`).toBe(0);
  });

  it("exits non-zero when a fake GOCSPX secret is planted in src/", async () => {
    // Plant a fake secret synchronously
    writeFileSync(FAKE_SECRET_FILE, 'const key = "GOCSPX-fake-secret-test";\n');
    try {
      const { code, stdout } = await runScript();
      expect(code, `expected non-zero exit. stdout: ${stdout}`).not.toBe(0);
    } finally {
      // Clean up synchronously after the assertion
      unlinkSync(FAKE_SECRET_FILE);
    }
  });
});
