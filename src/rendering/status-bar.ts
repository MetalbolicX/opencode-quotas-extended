// Status thresholds + progress bar. Defaults: OK < 0.5 | WRN [0.5, 0.8) | ERR [0.8, ∞). Unlimited → OK.
import { ansiColor, dim } from "./colors.js";

export interface StatusResult {
  readonly code: "OK" | "WRN" | "ERR" | "UNK";
  readonly ratio: number | null;
}

export interface Gradient { readonly threshold: number; readonly color: string; }
export interface BarOptions {
  readonly width?: number;
  readonly filledChar?: string;
  readonly emptyChar?: string;
  /** Static color name — when set, bar is wrapped in ANSI codes for that color. */
  readonly colorName?: string;
  /** When true, return "[<bar>] " with brackets and trailing space. */
  readonly framed?: boolean;
  /**
   * When "filled", the filled portion uses colorName and the empty portion uses dim.
   * Only meaningful when colorName is also set.
   */
  readonly colorSplit?: "filled" | "none";
}

const DEFAULT_GRADIENTS: Gradient[] = [
  { threshold: 0.5, color: "green" },
  { threshold: 0.8, color: "yellow" },
  { threshold: 1.0, color: "red" },
];

const _C = (c: string): StatusResult["code"] =>
  c === "green" ? "OK" : c === "yellow" ? "WRN" : c === "red" ? "ERR" : "UNK";

export function getStatus(used: number, limit: number | null, gradients: Gradient[] = DEFAULT_GRADIENTS): StatusResult {
  if (limit === null) return { code: "OK", ratio: null };
  if (used === 0) return { code: "OK", ratio: 0 };
  const ratio = used / limit;
  for (const g of gradients) { if (ratio < g.threshold) return { code: _C(g.color), ratio }; }
  return { code: _C(gradients[gradients.length - 1].color), ratio };
}

export function renderBar(ratio: number, opts: BarOptions = {}): string {
  const w = opts.width ?? 10, fc = opts.filledChar ?? "█", ec = opts.emptyChar ?? ".";
  const clamped = Math.min(Math.max(ratio, 0), 1);
  const filled = Math.round(clamped * w);
  const empty = w - filled;

  const useColorSplit = opts.colorSplit === "filled" && opts.colorName;

  let filledPart: string;
  let emptyPart: string;

  if (useColorSplit) {
    filledPart = ansiColor(opts.colorName!, fc.repeat(filled));
    emptyPart = dim(ec.repeat(empty));  // wrap entire empty portion as one chunk
  } else if (opts.colorName) {
    const bar = fc.repeat(filled) + ec.repeat(empty);
    filledPart = ansiColor(opts.colorName, bar);
    emptyPart = "";
  } else {
    filledPart = fc.repeat(filled) + ec.repeat(empty);
    emptyPart = "";
  }

  const bar = filledPart + emptyPart;
  if (opts.framed) return `[${bar}] `;
  return bar;
}
