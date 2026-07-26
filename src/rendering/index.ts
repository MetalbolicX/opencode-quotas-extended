// Renderer barrel + factory.
export { getStatus, renderBar } from "./status-bar.js";
export type { StatusResult, Gradient, BarOptions } from "./status-bar.js";
export { TableRenderer, JsonRenderer, MarkdownRenderer } from "./renderers.js";
import { TableRenderer } from "./renderers.js";
import { JsonRenderer } from "./renderers.js";
import { MarkdownRenderer } from "./renderers.js";
import type { Renderer } from "../ports/renderer.js";
import type { RenderMode } from "../domain/types.js";

export function selectRenderer(mode: RenderMode): Renderer {
  if (mode === "json") return new JsonRenderer();
  if (mode === "markdown") return new MarkdownRenderer();
  return new TableRenderer();
}
