// Config loader — reads and validates .opencode/quotas.json using Ajv.
// Fails fast with a clear error if the config is missing or invalid.

import Ajv from "ajv";
import addFormats from "ajv-formats";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { RenderMode } from "../../domain/types.js";

const ajv = new Ajv({ allErrors: true, verbose: true });
addFormats(ajv);

// Dynamically load the schema at runtime (avoids build-time coupling)
function loadSchema() {
  const schemaPath = join(import.meta.dirname, "../../../schemas/quotas.schema.json");
  return JSON.parse(readFileSync(schemaPath, "utf-8"));
}

let _validate: ReturnType<typeof ajv.compile> | null = null;
function getValidate() {
  if (!_validate) {
    _validate = ajv.compile(loadSchema());
  }
  return _validate;
}

export interface QuotasConfig {
  readonly displayMode: RenderMode;
  readonly disabled: readonly string[];
  readonly aggregatedGroups: Readonly<Record<string, {
    readonly strategy: "most_critical" | "max" | "min" | "mean" | "median";
    readonly members: readonly string[];
  }>>;
  readonly historyMaxAgeHours: number;
  readonly pollingInterval: number;
  readonly predictionWindowMinutes: number;
  readonly predictionShortWindowMinutes: number;
  readonly showUnaggregated: boolean;
  readonly filterByCurrentModel?: boolean;
  readonly progressBar?: {
    readonly width?: number;
    readonly filledChar?: string;
    readonly emptyChar?: string;
    readonly color?: boolean;
    readonly gradients?: boolean;
  };
  readonly credentials?: Readonly<Record<string, { type: "api"; key: string } | { type: "env"; envVar: string }>>;
}

export const DEFAULTS: QuotasConfig = {
  displayMode: "table",
  disabled: [],
  aggregatedGroups: {},
  historyMaxAgeHours: 24,
  pollingInterval: 0,
  predictionWindowMinutes: 60,
  predictionShortWindowMinutes: 5,
  showUnaggregated: false,
};

/**
 * Loads and validates a quotas config file.
 * @param configPath - absolute path to .opencode/quotas.json
 * @returns the parsed and defaulted config
 * @throws ConfigValidationError on invalid config
 */
export function loadConfig(configPath: string): QuotasConfig {
  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(configPath, "utf-8"));
  } catch (err: unknown) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { ...DEFAULTS };
    }
    throw new ConfigValidationError(`Failed to read config file: ${configPath}`, err as Error);
  }

  const validate = getValidate();
  const valid = validate(raw);

  if (!valid) {
    const errors = validate.errors?.map(
      (e) => `${e.instancePath || "/"} ${e.message ?? "unknown error"}`,
    ).join("; ") ?? "unknown error";
    throw new ConfigValidationError(`Invalid quotas config: ${errors}`);
  }

  return { ...DEFAULTS, ...(raw as Partial<QuotasConfig>) };
}

export class ConfigValidationError extends Error {
  readonly code = "CONFIG_VALIDATION_ERROR";
  constructor(message: string, cause?: Error) {
    super(message);
    this.name = "ConfigValidationError";
    this.cause = cause;
  }
}
