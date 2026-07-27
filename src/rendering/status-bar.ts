// Status thresholds + progress bar. Defaults: OK < 0.5 | WRN [0.5, 0.8) | ERR [0.8, ∞). Unlimited → OK.
import { ansiColor } from "./colors.js";

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
  const w = opts.width ?? 20, fc = opts.filledChar ?? "█", ec = opts.emptyChar ?? "░";
  const filled = Math.round(Math.min(Math.max(ratio, 0), 1) * w);
  const bar = fc.repeat(filled) + ec.repeat(w - filled);
  if (!opts.colorName) return bar;
  return ansiColor(opts.colorName, bar);
}
