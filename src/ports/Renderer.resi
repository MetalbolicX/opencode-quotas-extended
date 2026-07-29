// Renderer — application renders quota output through this port (DIP).

open Domain

type progressBarConfig = {
  width: float,
  filledChar: string,
  emptyChar: string,
  color: bool,
  gradients: bool,
}

type renderContext = {
  mode: renderMode,
  /** Static color name (e.g. "green", "brightRed") or undefined for no color. */
  color: option<string>,
  /** When true, renderer emits a compact layout (footer-friendly). */
  compact: option<bool>,
  progressBar: option<progressBarConfig>,
  /** Override terminal width for snapshot tests / CI. Defaults to process.stdout.columns clamped [60,80]. */
  terminalWidth: option<float>,
  /** Branded header for ASCII frame. */
  header: option<{
    brand: string,
    plan: option<string>,
  }>,
  t: translator,
}

and translator = {
  t: (string, option<dict<string>>) => string,
}

type renderer = {
  render: (array<quotaData>, renderContext) => string,
}
