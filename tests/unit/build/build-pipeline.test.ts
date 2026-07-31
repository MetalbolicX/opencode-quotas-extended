// WU-2 build pipeline tests — strict TDD RED first.
// These tests verify that codegen is wired into the package.json lifecycle hooks.
// They run against package.json scripts and the actual lifecycle commands.
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, unlinkSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const PACKAGE_JSON_PATH = join(PROJECT_ROOT, "package.json");
const CODegen_PATH = join(PROJECT_ROOT, "scripts", "codegen.mjs");
const CODegen_SCHEMA_OUT = join(PROJECT_ROOT, "src", "Infra", "ConfigLoader", "Schema.res");
const CODegen_CATALOG_OUT = join(PROJECT_ROOT, "src", "i18n", "Translator", "EnCatalog.res");

// Sentinel value we write to detect whether prebuild/preres:build/postinstall actually ran
const SENTINEL_VALUE = "PREBUILD_WIRE_CHECK_2024";
const SENTINEL_PLACEHOLDER = "PREBUILD_WIRE_CHECK_PLACEHOLDER";

function readPackageJson() {
  return JSON.parse(readFileSync(PACKAGE_JSON_PATH, "utf8"));
}

function runPnpmScript(scriptName, cwd = PROJECT_ROOT) {
  return new Promise((resolve) => {
    const proc = spawn("pnpm", ["run", scriptName], { cwd, stdio: "pipe" });
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d));
    proc.stderr.on("data", (d) => (stderr += d));
    proc.on("close", (code) => resolve({ exitCode: code, stdout, stderr }));
  });
}

function runCodegen(cwd = PROJECT_ROOT) {
  return new Promise((resolve) => {
    const proc = spawn("node", [CODegen_PATH], { cwd, stdio: "pipe" });
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d));
    proc.stderr.on("data", (d) => (stderr += d));
    proc.on("close", (code) => resolve({ exitCode: code, stdout, stderr }));
  });
}

function writeSentinelIntoGeneratedFile(filePath) {
  const content = readFileSync(filePath, "utf8");
  // Insert sentinel into the JSON payload of Schema.res or somewhere visible in Catalog.res
  if (filePath.endsWith("Schema.res")) {
    // Schema.res: insert into the %raw content (add a comment-like marker)
    return content + `\n// ${SENTINEL_VALUE}\n`;
  } else {
    // Catalog.res: append to the file
    return content + `\n// ${SENTINEL_VALUE}\n`;
  }
}

function generatedFileHasSentinel(filePath) {
  if (!existsSync(filePath)) return false;
  return readFileSync(filePath, "utf8").includes(SENTINEL_VALUE);
}

describe("package.json lifecycle scripts exist", () => {
  it("codegen script must exist in package.json", () => {
    const pkg = readPackageJson();
    expect(pkg.scripts).toHaveProperty("codegen");
    expect(pkg.scripts.codegen).toContain("codegen.mjs");
  });

  it("prebuild script must exist in package.json", () => {
    const pkg = readPackageJson();
    expect(pkg.scripts).toHaveProperty("prebuild");
  });

  it("preres:build script must exist in package.json", () => {
    const pkg = readPackageJson();
    expect(pkg.scripts).toHaveProperty("preres:build");
  });

  it("postinstall script must exist in package.json", () => {
    const pkg = readPackageJson();
    expect(pkg.scripts).toHaveProperty("postinstall");
  });

  it("build script must still invoke rolldown (not changed)", () => {
    const pkg = readPackageJson();
    expect(pkg.scripts.build).toContain("rolldown");
    expect(pkg.scripts.build).not.toContain("codegen");
  });

  it("res:build script must still invoke rescript build (not changed)", () => {
    const pkg = readPackageJson();
    expect(pkg.scripts["res:build"]).toContain("rescript");
    expect(pkg.scripts["res:build"]).not.toContain("codegen");
  });
});

describe("pnpm codegen — script is functional", () => {
  afterAll(() => {
    // Clean up generated files after tests
    try { unlinkSync(CODegen_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("pnpm codegen exits 0", async () => {
    const { exitCode } = await runPnpmScript("codegen");
    expect(exitCode).toBe(0);
  });

  it("pnpm codegen produces the generated schema file", async () => {
    await runPnpmScript("codegen");
    expect(existsSync(CODegen_SCHEMA_OUT)).toBe(true);
  });

  it("pnpm codegen produces the generated catalog file", async () => {
    await runPnpmScript("codegen");
    expect(existsSync(CODegen_CATALOG_OUT)).toBe(true);
  });
});

describe("prebuild hook — runs codegen before build", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("prebuild overwrites a stale generated file with canonical content", async () => {
    // Step 1: Generate clean files first
    await runCodegen();

    // Step 2: Corrupt the schema file by inserting sentinel
    if (!existsSync(CODegen_SCHEMA_OUT)) {
      // The file may not exist if we're running in isolation — generate it
      await runCodegen();
    }
    const corruptedContent = readFileSync(CODegen_SCHEMA_OUT, "utf8") + `\n// ${SENTINEL_PLACEHOLDER}`;
    writeFileSync(CODegen_SCHEMA_OUT, corruptedContent);
    expect(existsSync(CODegen_SCHEMA_OUT)).toBe(true);
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).toContain(SENTINEL_PLACEHOLDER);

    // Step 3: Run prebuild — should regenerate the file (overwrite with canonical)
    const { exitCode } = await runPnpmScript("prebuild");
    // prebuild runs codegen AND res:build; we only care that codegen ran
    expect(exitCode).toBe(0);

    // Step 4: Verify the sentinel is GONE (codegen overwrote the stale file)
    expect(existsSync(CODegen_SCHEMA_OUT)).toBe(true);
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).not.toContain(SENTINEL_PLACEHOLDER);
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).toContain("GENERATED");
  });
});

describe("preres:build hook — runs codegen before rescript build", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("preres:build overwrites a stale generated file with canonical content", async () => {
    // Step 1: Generate clean files first
    await runCodegen();

    // Step 2: Corrupt the catalog file
    if (!existsSync(CODegen_CATALOG_OUT)) {
      await runCodegen();
    }
    const corruptedContent = readFileSync(CODegen_CATALOG_OUT, "utf8") + `\n// ${SENTINEL_PLACEHOLDER}`;
    writeFileSync(CODegen_CATALOG_OUT, corruptedContent);
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).toContain(SENTINEL_PLACEHOLDER);

    // Step 3: Run preres:build
    const { exitCode } = await runPnpmScript("preres:build");
    expect(exitCode).toBe(0);

    // Step 4: Verify the sentinel is GONE (codegen ran and overwrote)
    expect(existsSync(CODegen_CATALOG_OUT)).toBe(true);
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).not.toContain(SENTINEL_PLACEHOLDER);
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).toContain("GENERATED");
  });
});

describe("postinstall hook — bootstraps generated files on fresh install", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("postinstall generates files when they are missing", async () => {
    // Step 1: Ensure generated files do NOT exist (simulate fresh clone)
    try { unlinkSync(CODegen_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_CATALOG_OUT); } catch { /* ignore */ }
    expect(existsSync(CODegen_SCHEMA_OUT)).toBe(false);
    expect(existsSync(CODegen_CATALOG_OUT)).toBe(false);

    // Step 2: Run postinstall (this is what pnpm install triggers)
    const { exitCode } = await runPnpmScript("postinstall");
    expect(exitCode).toBe(0);

    // Step 3: Verify generated files now exist
    expect(existsSync(CODegen_SCHEMA_OUT)).toBe(true);
    expect(existsSync(CODegen_CATALOG_OUT)).toBe(true);

    // Step 4: Verify content is valid (contains GENERATED marker, schema has %raw)
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).toContain("GENERATED");
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).toContain("%raw(`");
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).toContain("GENERATED");
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).toContain("Dict.fromArray");
  });

  it("postinstall overwrites stale generated files with canonical content", async () => {
    // Step 1: Generate clean files
    await runCodegen();

    // Step 2: Corrupt both files
    const corruptedSchema = readFileSync(CODegen_SCHEMA_OUT, "utf8") + `\n// ${SENTINEL_PLACEHOLDER}`;
    writeFileSync(CODegen_SCHEMA_OUT, corruptedSchema);
    const corruptedCatalog = readFileSync(CODegen_CATALOG_OUT, "utf8") + `\n// ${SENTINEL_PLACEHOLDER}`;
    writeFileSync(CODegen_CATALOG_OUT, corruptedCatalog);

    // Step 3: Run postinstall
    const { exitCode } = await runPnpmScript("postinstall");
    expect(exitCode).toBe(0);

    // Step 4: Verify both files are restored to canonical (sentinel gone)
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).not.toContain(SENTINEL_PLACEHOLDER);
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).not.toContain(SENTINEL_PLACEHOLDER);
    expect(readFileSync(CODegen_SCHEMA_OUT, "utf8")).toContain("GENERATED");
    expect(readFileSync(CODegen_CATALOG_OUT, "utf8")).toContain("GENERATED");
  });
});

describe("pnpm build — runs codegen → res:build → rolldown in order", () => {
  // This is an integration test verifying the full chain works
  afterAll(() => {
    try { unlinkSync(CODegen_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("pnpm build succeeds and produces dist/cli/index.js", async () => {
    // First ensure codegen ran so we have generated files
    await runCodegen();

    // Run the full build chain (may take up to 60s due to rescript compilation)
    const { exitCode, stdout, stderr } = await runPnpmScript("build");

    // Build should succeed
    expect(exitCode).toBe(0), `pnpm build failed: ${stderr}`;

    // rolldown should have produced the bundle
    const distCli = join(PROJECT_ROOT, "dist", "cli", "index.js");
    expect(existsSync(distCli)).toBe(true), "dist/cli/index.js was not produced";
  });
}, 120000); // 120s timeout for full build chain
