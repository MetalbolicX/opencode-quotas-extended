// src/rendering/Renderers.resi
// Table, JSON, and Markdown renderers.

type translator = {
  t: (string, option<dict<string>>) => string,
}

type progressBarConfig = {
  width: option<float>,
  filledChar: option<string>,
  emptyChar: option<string>,
  color: option<bool>,
  gradients: option<bool>,
}

type renderContext = {
  mode: Domain.renderMode,
  color: option<string>,
  compact: option<bool>,
  progressBar: option<progressBarConfig>,
  terminalWidth: option<float>,
  header: option<{brand: string, plan: option<string>}>,
  t: translator,
}

type renderer = {
  render: (array<Domain.quotaData>, renderContext) => string,
}

let selectRenderer: (Domain.renderMode) => renderer
