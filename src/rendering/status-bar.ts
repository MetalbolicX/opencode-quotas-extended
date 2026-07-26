// Status thresholds + progress bar. Defaults: OK < 0.5 | WRN [0.5, 0.8) | ERR [0.8, ∞). Unlimited → OK.

export interface StatusResult {
  readonly code: "OK" | "WRN" | "ERR" | "UNK";
  readonly ratio: number | null;
}

export interface Gradient { readonly threshold: number; readonly color: string; }
export interface BarOptions {
  readonly width?: number;
  readonly filledChar?: string;
  readonly emptyChar?: string;
  readonly color?: boolean;
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

function _color(): boolean {
  if (process.env.NO_COLOR !== undefined) return false;
  if (process.env.FORCE_COLOR !== undefined) return true;
  return process.stdout.isTTY === true;
}

export function renderBar(ratio: number, opts: BarOptions = {}): string {
  const w = opts.width ?? 20, fc = opts.filledChar ?? "█", ec = opts.emptyChar ?? "░";
  const use = opts.color ?? _color();
  const filled = Math.round(Math.min(Math.max(ratio, 0), 1) * w);
  const bar = fc.repeat(filled) + ec.repeat(w - filled);
  if (!use) return bar;
  const c = ratio >= 0.8 ? "31" : ratio >= 0.5 ? "33" : "32";
  return `\x1b[${c}m${bar}\x1b[0m`;
}
