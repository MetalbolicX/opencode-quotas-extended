// Config loader — reads and validates .opencode/quotas.json using Ajv.
// Fails fast with a clear error if the config is missing or invalid.

import Ajv from "ajv";
import addFormats from "ajv-formats";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { RenderMode } from "../../domain/types.js";
import type { Logger } from "../../ports/logger.js";

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
  /** Controls footer visibility: false=hidden, true=show (compact=simple, full=detailed). Orthogonal to displayMode. */
  readonly show?: boolean;
  readonly filterByCurrentModel?: boolean;
  readonly progressBar?: {
    readonly width?: number;
    readonly filledChar?: string;
    readonly emptyChar?: string;
    readonly color?: boolean;
    readonly gradients?: boolean;
  };
  readonly credentials?: Readonly<Record<string, { type: "api"; key: string } | { type: "env"; envVar: string }>>;
  readonly anthropic?: {
    readonly orgId?: string;
  };
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
  show: true,
};

/**
 * Loads and validates a quotas config file.
 * @param configPath - absolute path to .opencode/quotas.json
 * @param logger - optional logger to receive deprecation warnings
 * @returns the parsed and defaulted config
 * @throws ConfigValidationError on invalid config
 */
export function loadConfig(configPath: string, logger?: Logger): QuotasConfig {
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

  // Emit deprecation warnings for deprecated fields, then strip them so they don't propagate.
  const rawObj = raw as Partial<QuotasConfig>;
  const deprecatedKeys = ["show", "pollingInterval"] as const;
  for (const field of deprecatedKeys) {
    if (field in rawObj) {
      const msg = `[opencode-quotas] config field '${field}' is deprecated and ignored`;
      if (logger) {
        logger.warn("config.deprecated-field", { field });
      } else {
        console.warn(msg);
      }
    }
  }
  // footer exists in the schema but was removed from the QuotasConfig interface — check raw only.
  if ("footer" in (raw as object)) {
    const msg = `[opencode-quotas] config field 'footer' is deprecated and ignored`;
    if (logger) {
      logger.warn("config.deprecated-field", { field: "footer" });
    } else {
      console.warn(msg);
    }
  }

  // Strip deprecated keys so they don't flow into the returned config.
  const { show: _show, pollingInterval: _pollingInterval, ...strippedRaw } = rawObj;

  return { ...DEFAULTS, ...(strippedRaw as Partial<QuotasConfig>) };
}

export class ConfigValidationError extends Error {
  readonly code = "CONFIG_VALIDATION_ERROR";
  constructor(message: string, cause?: Error) {
    super(message);
    this.name = "ConfigValidationError";
    this.cause = cause;
  }
}

/**
 * Resolves the Anthropic organization ID from three sources in priority order:
 * 1. quotas.json  → config.anthropic.orgId
 * 2. auth.json    → auth.anthropic.orgId | auth.anthropic.org
 * 3. env          → ANTHROPIC_ORG_ID
 *
 * @param cfg  — the loaded QuotasConfig
 * @param auth — the auth record (keyed by provider, e.g. { anthropic: { orgId?, org? } })
 * @param env  — process.env
 * @throws Error with a clear, actionable message if no orgId is found in any source.
 */
export function resolveAnthropicOrgId(
  cfg: QuotasConfig,
  auth: Record<string, unknown> | undefined,
  env: NodeJS.ProcessEnv,
): string {
  const fromCfg = cfg.anthropic?.orgId;
  if (typeof fromCfg === "string" && fromCfg.trim().length > 0) return fromCfg.trim();
  const anthropicAuth = auth?.anthropic as { org?: string; orgId?: string } | undefined;
  const fromAuth = anthropicAuth?.orgId ?? anthropicAuth?.org;
  if (typeof fromAuth === "string" && fromAuth.length > 0) return fromAuth;
  const fromEnv = env.ANTHROPIC_ORG_ID;
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;
  throw new Error(
    "Anthropic org_id missing: set anthropic.orgId in quotas.json, " +
    "anthropic.orgId (or anthropic.org) in auth.json, " +
    "or ANTHROPIC_ORG_ID env variable",
  );
}
