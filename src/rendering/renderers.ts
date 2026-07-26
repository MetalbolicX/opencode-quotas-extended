// Table, JSON, and Markdown renderers — all in one file for line-budget efficiency.
import type { Renderer, RenderContext } from "../ports/renderer.js";
import type { QuotaData } from "../domain/types.js";
import { getStatus, renderBar } from "./status-bar.js";

function fmtPct(r: number | null): string { return r === null ? "∞" : `${Math.round(r * 100)}%`; }
function fmtReset(d: Date | null): string {
  if (!d) return "—";
  const diff = d.getTime() - Date.now();
  if (diff <= 0) return "now";
  const m = Math.floor(diff / 60000);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

function _autoWidth(quotas: readonly QuotaData[]): Record<string, number> {
  const w: Record<string, number> = { status: 6, name: 4, bar: 5, percent: 4, reset: 5, ettl: 4 };
  for (const q of quotas) w.name = Math.max(w.name, q.providerName.length);
  return w;
}

const COLS: (keyof ReturnType<typeof _autoWidth>)[] = ["status", "name", "bar", "percent", "reset", "ettl"];

export class TableRenderer implements Renderer {
  render(quotas: readonly QuotaData[], ctx: RenderContext): string {
    const { t, noColor = false } = ctx;
    const barOpts = ctx.progressBar ?? {};
    const widths = _autoWidth(quotas);
    const pad = (s: string, col: string) => s.padEnd(widths[col]);
    const header = COLS.map(c => pad(t.t(`header.${c}`), c)).join("   ").trimEnd();
    const rows = quotas.map(q => {
      const s = getStatus(q.used, q.limit);
      return COLS.map(c => pad(c === "bar" ? renderBar(s.ratio ?? 0, { ...barOpts, color: !noColor })
        : c === "percent" ? fmtPct(s.ratio)
        : c === "reset" ? fmtReset(q.reset)
        : c === "ettl" ? (q.predictedReset ? fmtReset(q.predictedReset) : "—")
        : c === "status" ? s.code : q.providerName, c)).join("   ").trimEnd();
    });
    return [header, ...rows].join("\n");
  }
}

export class JsonRenderer implements Renderer {
  render(quotas: readonly QuotaData[], _ctx: RenderContext): string {
    return JSON.stringify({ fetchedAt: new Date().toISOString(), quotas: quotas.map(q => {
      const s = getStatus(q.used, q.limit);
      return { id: q.id, provider: q.providerName, used: q.used, limit: q.limit, unit: q.unit, status: s.code, ratio: s.ratio, reset: q.reset?.toISOString() ?? null, predictedReset: q.predictedReset?.toISOString() ?? null, window: q.window };
    })}, null, 2);
  }
}

export class MarkdownRenderer implements Renderer {
  render(quotas: readonly QuotaData[], _ctx: RenderContext): string {
    const rows = quotas.map(q => {
      const s = getStatus(q.used, q.limit);
      return `| ${q.providerName} | ${s.code} | ${fmtPct(s.ratio)} | ${fmtReset(q.reset)} | ${q.predictedReset ? fmtReset(q.predictedReset) : "—"} |`;
    });
    return ["| Name | Status | % | Reset | ETTL |", "|------|--------|-------|-------|-------|", ...rows].join("\n");
  }
}
