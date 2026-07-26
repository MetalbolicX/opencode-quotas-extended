import { describe, it, expect } from "vitest";
import Ajv from "ajv";
import addFormats from "ajv-formats";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Derive project root from this test file's location: tests/unit/config/*.test.ts → project root
const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

// Build and return the compiled validate function (avoids ajv.schema default issue in Ajv 8)
function buildValidator() {
  const ajv = new Ajv({ allErrors: true, verbose: true });
  addFormats(ajv);
  const schema = JSON.parse(
    readFileSync(join(PROJECT_ROOT, "schemas/quotas.schema.json"), "utf-8"),
  );
  const validate = ajv.compile(schema);
  return { ajv, validate, schema };
}

describe("quotas.schema.json", () => {
  it("schema file must exist and be valid JSON", () => {
    expect(() => buildValidator()).not.toThrow();
  });

  it("must validate a minimal valid config", () => {
    const { validate, ajv } = buildValidator();
    const valid = {
      displayMode: "table",
      disabled: [],
      aggregatedGroups: {},
      historyMaxAgeHours: 24,
      pollingInterval: 0,
      predictionWindowMinutes: 60,
      predictionShortWindowMinutes: 5,
      showUnaggregated: false,
    };
    const result = validate(valid);
    expect(result, ajv.errorsText()).toBe(true);
  });

  it("must reject an unknown top-level key", () => {
    const { validate } = buildValidator();
    const invalid = {
      displayMode: "table",
      unknownField: "should not exist",
      disabled: [],
      aggregatedGroups: {},
      historyMaxAgeHours: 24,
      pollingInterval: 0,
      predictionWindowMinutes: 60,
      predictionShortWindowMinutes: 5,
      showUnaggregated: false,
    };
    const result = validate(invalid);
    expect(result).toBe(false);
    expect(validate.errors).not.toBeNull();
    // Ajv reports additional-properties violations with a keyword message, not field name
    const errorText = validate.errors!.map((e) => e.instancePath + " " + e.message).join("; ");
    expect(errorText).toMatch(/additional/i);
  });

  it("must reject wrong type for displayMode", () => {
    const { validate, ajv } = buildValidator();
    const invalid = { displayMode: 123, disabled: [], aggregatedGroups: {} } as any;
    const result = validate(invalid);
    expect(result).toBe(false);
  });

  it("must reject displayMode value not in enum", () => {
    const { validate, ajv } = buildValidator();
    const invalid = { displayMode: "invalid-mode", disabled: [], aggregatedGroups: {} } as any;
    const result = validate(invalid);
    expect(result).toBe(false);
  });

  it("must reject negative pollingInterval", () => {
    const { validate, ajv } = buildValidator();
    const invalid = {
      displayMode: "table",
      disabled: [],
      aggregatedGroups: {},
      pollingInterval: -1,
    } as any;
    const result = validate(invalid);
    expect(result).toBe(false);
  });

  it("must accept all valid displayMode values", () => {
    const { validate, ajv } = buildValidator();
    for (const mode of ["table", "json", "markdown"]) {
      const valid = { displayMode: mode, disabled: [], aggregatedGroups: {} };
      const result = validate(valid);
      expect(result, `displayMode=${mode} should be valid`).toBe(true);
    }
  });

  it("must accept progressBar with all optional fields", () => {
    const { validate, ajv } = buildValidator();
    const valid = {
      displayMode: "table",
      disabled: [],
      aggregatedGroups: {},
      progressBar: {
        width: 20,
        filledChar: "█",
        emptyChar: "░",
        color: true,
        gradients: true,
      },
    };
    const result = validate(valid);
    expect(result, ajv.errorsText()).toBe(true);
  });

  it("must accept credentials per-provider override", () => {
    const { validate, ajv } = buildValidator();
    const valid = {
      displayMode: "table",
      disabled: [],
      aggregatedGroups: {},
      credentials: {
        openai: { type: "api", key: "sk-test" },
        anthropic: { type: "env", envVar: "ANTHROPIC_API_KEY" },
      },
    };
    const result = validate(valid);
    expect(result, ajv.errorsText()).toBe(true);
  });

  it("must accept aggregation config with all strategy values", () => {
    const { validate, ajv } = buildValidator();
    const valid = {
      displayMode: "table",
      disabled: [],
      aggregatedGroups: {
        "coding-plans": {
          strategy: "most_critical",
          members: ["openai", "anthropic"],
        },
      },
    };
    const result = validate(valid);
    expect(result, ajv.errorsText()).toBe(true);
  });

  it("must accept filterByCurrentModel boolean", () => {
    const { validate, ajv } = buildValidator();
    const valid = {
      displayMode: "table",
      disabled: [],
      aggregatedGroups: {},
      filterByCurrentModel: true,
    };
    const result = validate(valid);
    expect(result, ajv.errorsText()).toBe(true);
  });
});
