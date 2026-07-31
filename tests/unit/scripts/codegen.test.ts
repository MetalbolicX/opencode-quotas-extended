// WU-1 codegen tests — strict TDD RED first.
// These tests describe the expected behavior of scripts/codegen.mjs.
// They run against the script directly using Node child_process.
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, unlinkSync, existsSync, mkdirSync, renameSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const CODegen_PATH = join(PROJECT_ROOT, "scripts", "codegen.mjs");
// Generated files live in subdirectories to avoid ReScript namespace self-reference conflict.
// File "src/Infra/ConfigLoader/Schema.res" compiles to module "ConfigLoader.Schema".
const CODegen_TEST_SCHEMA_OUT = join(PROJECT_ROOT, "src", "Infra", "ConfigLoader", "Schema.res");
const CODegen_TEST_CATALOG_OUT = join(PROJECT_ROOT, "src", "i18n", "Translator", "EnCatalog.res");
const CANONICAL_SCHEMA = join(PROJECT_ROOT, "schemas", "quotas.schema.json");
const CANONICAL_CATALOG = join(PROJECT_ROOT, "src", "i18n", "locales", "en.json");

// Helper: run codegen.mjs and return { exitCode, stdout, stderr }
function runCodegen(args = [], cwd = PROJECT_ROOT) {
  return new Promise((resolve) => {
    const proc = spawn("node", [CODegen_PATH, ...args], { cwd, stdio: "pipe" });
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d));
    proc.stderr.on("data", (d) => (stderr += d));
    proc.on("close", (code) => resolve({ exitCode: code, stdout, stderr }));
  });
}

// Helper: extract JSON payload from %raw(`...`) in a generated .res file
// The generated schema uses simple format: %raw(`{JSON}`) with no nested template literals.
function extractRawJsonFromRes(resPath) {
  const content = readFileSync(resPath, "utf8");
  const startMarker = "%raw(`";
  const startIdx = content.indexOf(startMarker);
  if (startIdx === -1) throw new Error(`No %raw(\` found in ${resPath}`);

  // Opening backtick is 5 chars after "%raw("
  const outerOpenIdx = startIdx + 5;
  // Find closing backtick: first unescaped ` preceded by \n}\n
  let innerCloseIdx = -1;
  for (let i = outerOpenIdx + 1; i < content.length; i++) {
    if (content[i] === "`") {
      let numBackslashes = 0;
      for (let j = i - 1; j >= 0 && content[j] === "\\"; j--) numBackslashes++;
      if (numBackslashes % 2 === 0) {
        const prev3 = content.slice(Math.max(0, i - 3), i);
        if (prev3 === "\n}\n") {
          innerCloseIdx = i;
          break;
        }
      }
    }
  }
  if (innerCloseIdx === -1) throw new Error("No closing backtick found in generated schema");

  const rawJson = content.slice(outerOpenIdx + 1, innerCloseIdx);
  return rawJson.replace(/\\`/g, "`").replace(/\\\$/g, "$");
}

// Helper: parse Dict.fromArray content from generated .res file
function extractCatalogFromRes(resPath) {
  const content = readFileSync(resPath, "utf8");
  const result = {};
  // Match lines like:  ("key", "value"),
  const tupleRegex = /\("([^"]+)",\s*"([^"]*)"\)/g;
  let m;
  while ((m = tupleRegex.exec(content)) !== null) {
    result[m[1]] = m[2];
  }
  return result;
}

describe("codegen.mjs — RED tests (script does not exist yet)", () => {
  it("script file must exist", () => {
    expect(existsSync(CODegen_PATH)).toBe(true);
  });

  it("canonical schema file must exist", () => {
    expect(existsSync(CANONICAL_SCHEMA)).toBe(true);
  });

  it("canonical catalog file must exist", () => {
    expect(existsSync(CANONICAL_CATALOG)).toBe(true);
  });
});

describe("codegen.mjs — schema emission (REQ-CODEGEN-1)", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_TEST_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_TEST_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("emits ConfigLoader.Schema.res with %raw containing canonical schema JSON", async () => {
    const { exitCode } = await runCodegen();
    expect(exitCode).toBe(0);

    expect(existsSync(CODegen_TEST_SCHEMA_OUT)).toBe(true);

    const canonicalSchema = JSON.parse(readFileSync(CANONICAL_SCHEMA, "utf8"));
    const embeddedJson = extractRawJsonFromRes(CODegen_TEST_SCHEMA_OUT);
    const parsed = JSON.parse(embeddedJson);

    // Round-trip: parsed must deep-equal canonical
    expect(parsed).toEqual(canonicalSchema);
  });

  it("generated schema file has correct module header comment", async () => {
    await runCodegen();
    const content = readFileSync(CODegen_TEST_SCHEMA_OUT, "utf8");
    expect(content).toContain("GENERATED");
    expect(content).toContain("codegen.mjs");
  });
});

describe("codegen.mjs — catalog emission (REQ-CODEGEN-2)", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_TEST_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_TEST_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("emits Translator.EnCatalog.res with Dict.fromArray covering all en.json entries", async () => {
    const { exitCode } = await runCodegen();
    expect(exitCode).toBe(0);

    expect(existsSync(CODegen_TEST_CATALOG_OUT)).toBe(true);

    const canonicalCatalog = JSON.parse(readFileSync(CANONICAL_CATALOG, "utf8"));
    const generated = extractCatalogFromRes(CODegen_TEST_CATALOG_OUT);

    // Every canonical key/value must appear in generated catalog
    for (const [key, value] of Object.entries(canonicalCatalog)) {
      expect(generated, `missing key: ${key}`).toHaveProperty(key);
      expect(generated[key]).toBe(value);
    }
  });

  it("generated catalog file has correct module header comment", async () => {
    await runCodegen();
    const content = readFileSync(CODegen_TEST_CATALOG_OUT, "utf8");
    expect(content).toContain("GENERATED");
    expect(content).toContain("codegen.mjs");
  });
});

describe("codegen.mjs — idempotence (REQ-CODEGEN-4)", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_TEST_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_TEST_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("second run produces byte-identical output", async () => {
    await runCodegen();
    const schema1 = readFileSync(CODegen_TEST_SCHEMA_OUT);
    const catalog1 = readFileSync(CODegen_TEST_CATALOG_OUT);

    await runCodegen();
    const schema2 = readFileSync(CODegen_TEST_SCHEMA_OUT);
    const catalog2 = readFileSync(CODegen_TEST_CATALOG_OUT);

    expect(schema1.equals(schema2), "schema should be byte-identical on re-run").toBe(true);
    expect(catalog1.equals(catalog2), "catalog should be byte-identical on re-run").toBe(true);
  });
});

describe("codegen.mjs — round-trip / drift detection (REQ-CODEGEN-5)", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_TEST_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_TEST_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("corrupting the generated schema file is overwritten on next run", async () => {
    // First: generate clean files
    await runCodegen();
    const originalSchema = readFileSync(CODegen_TEST_SCHEMA_OUT, "utf8");

    // Deliberately corrupt the generated file (add a space to the JSON payload)
    const corruptedSchema = originalSchema.replace('"title":', '"title": "CORRUPTED",');
    writeFileSync(CODegen_TEST_SCHEMA_OUT, corruptedSchema);

    // Run codegen again — should fix the drift
    const { exitCode } = await runCodegen();
    expect(exitCode).toBe(0);

    const restoredSchema = readFileSync(CODegen_TEST_SCHEMA_OUT, "utf8");
    expect(restoredSchema).not.toContain("CORRUPTED");
    expect(restoredSchema).toEqual(originalSchema);
  });
});

describe("codegen.mjs — error handling", () => {
  it("missing canonical schema exits with code 2", async () => {
    const backupPath = CANONICAL_SCHEMA + ".bak";
    try {
      // Move canonical schema out of the way
      renameSync(CANONICAL_SCHEMA, backupPath);
      const { exitCode } = await runCodegen([]);
      expect(exitCode).toBe(2);
    } finally {
      // Restore
      if (existsSync(backupPath)) {
        renameSync(backupPath, CANONICAL_SCHEMA);
      }
    }
  });
});

describe("codegen.mjs — generated file structure", () => {
  afterAll(() => {
    try { unlinkSync(CODegen_TEST_SCHEMA_OUT); } catch { /* ignore */ }
    try { unlinkSync(CODegen_TEST_CATALOG_OUT); } catch { /* ignore */ }
  });

  it("ConfigLoader.Schema.res exports a schema binding of type JSON.t", async () => {
    await runCodegen();
    const content = readFileSync(CODegen_TEST_SCHEMA_OUT, "utf8");
    // Must contain the schema export
    expect(content).toMatch(/let schema:\s*JSON\.t/);
    // Must contain %raw with JSON template literal
    expect(content).toContain("%raw(`");
  });

  it("Translator.EnCatalog.res exports an enCatalog binding of type dict<string>", async () => {
    await runCodegen();
    const content = readFileSync(CODegen_TEST_CATALOG_OUT, "utf8");
    // Must contain Dict.fromArray
    expect(content).toContain("Dict.fromArray([");
    expect(content).toContain("let enCatalog:");
  });
});
