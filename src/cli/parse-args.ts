// WU-4 GREEN: CLI argument parser using node:util.parseArgs.
// Flags: -l/--list, -p/--provider, -c/--color, -m/--mode, -h/--help.
// Strict: unknown options throw. Mutual exclusion of -l and -p validated.
// REQ-CLI-1..5, REQ-COLOR-3.

import { parseArgs as nodeParseArgs } from "node:util";
import { COLOR_MAP } from "../rendering/colors.js";

export type RenderMode = "table" | "json" | "markdown";

export interface CliArgs {
  list: boolean;
  provider?: string;
  color?: string;
  mode: RenderMode;
  help: boolean;
}

const VALID_MODES: ReadonlySet<RenderMode> = new Set(["table", "json", "markdown"]);

const VALID_COLOR_NAMES = Object.keys(COLOR_MAP).join(", ");

export function parseArgs(argv: readonly string[]): CliArgs {
  const parsed = nodeParseArgs({
    args: argv as string[],
    options: {
      list: { type: "boolean", short: "l" },
      provider: { type: "string", short: "p" },
      color: { type: "string", short: "c" },
      mode: { type: "string", short: "m" },
      help: { type: "boolean", short: "h" },
    },
    strict: true,
    allowPositionals: false,
  });

  // REQ-CLI-1: default to list=true when no provider is given
  // (either explicit -l/--list OR no flags at all)
  const list = parsed.values.list === true || parsed.values.provider === undefined;

  // REQ-CLI-4: -l and -p are mutually exclusive
  if (list && parsed.values.provider !== undefined) {
    throw new Error("Cannot combine -l/--list with -p/--provider");
  }

  // REQ-CLI-3: validate color
  if (parsed.values.color !== undefined) {
    if (!Object.prototype.hasOwnProperty.call(COLOR_MAP, parsed.values.color as string)) {
      throw new Error(`Invalid color: ${parsed.values.color}. Valid: ${VALID_COLOR_NAMES}`);
    }
  }

  // REQ-CLI-2: validate mode (default table)
  const mode = (parsed.values.mode as RenderMode | undefined) ?? "table";
  if (!VALID_MODES.has(mode)) {
    throw new Error(`Invalid mode: ${mode}. Valid: table, json, markdown`);
  }

  return {
    list,
    provider: parsed.values.provider as string | undefined,
    color: parsed.values.color as string | undefined,
    mode,
    help: parsed.values.help === true,
  };
}
