// Renderer — application renders quota output through this port (DIP).

import type { QuotaData } from "../domain/types.js";
import type { RenderMode } from "../domain/types.js";

export interface RenderContext {
  readonly mode: RenderMode;
  /** Static color name (e.g. "green", "brightRed") or undefined for no color. */
  readonly color?: string;
  /** When true, renderer emits a compact layout (footer-friendly). */
  readonly compact?: boolean;
  readonly progressBar?: {
    readonly width: number;
    readonly filledChar: string;
    readonly emptyChar: string;
    readonly color: boolean;
    readonly gradients: boolean;
  };
  /** Override terminal width for snapshot tests / CI. Defaults to process.stdout.columns clamped [60,80]. */
  readonly terminalWidth?: number;
  /** Branded header for ASCII frame. */
  readonly header?: { readonly brand: string; readonly plan?: string };
  readonly t: Translator;
}

export interface Renderer {
  render(data: readonly QuotaData[], ctx: RenderContext): string;
}

export interface Translator {
  t(key: string, vars?: Record<string, string | number>): string;
}
