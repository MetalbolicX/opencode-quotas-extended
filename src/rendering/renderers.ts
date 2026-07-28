// Table, JSON, and Markdown renderers — all in one file for line-budget efficiency.
import type { Renderer, RenderContext } from "../ports/renderer.js";
import type { QuotaData } from "../domain/types.js";
import { getStatus, renderBar } from "./status-bar.js";

const fmtPct = (r: number | null): string => { return r === null ? "∞" : `${Math.round(r * 100)}%`; }
const fmtReset = (d: Date | null): string => {
  if (!d) return "—";
  const diff = d.getTime() - Date.now();
  if (diff <= 0) return "now";
  const m = Math.floor(diff / 60000);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

const humanize = (n: number): string => {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1).replace(/\.0$/, "")}K`;
  return String(n);
}

const usageText = (q: QuotaData, ratio: number | null): string => {
  if (q.unit === "%") {
    if (q.limit === null) return "unlimited";
    const pct = Math.round((ratio ?? 0) * 100);
    return `${pct}% used`;
  }
  if (q.unit === "requests") {
    if (q.limit === null) return "no limit";
    return `${q.used} / ${q.limit} requests`;
  }
  if (q.unit === "tokens") {
    if (q.limit === null) return "no limit";
    return `${humanize(q.used)} / ${humanize(q.limit)} tokens`;
  }
  if (q.unit === "credits") {
    if (q.limit === null) return `balance: ${q.used}`;
    return `balance: ${q.used}`;
  }
  // fallback: show used/limit with unit
  if (q.limit === null) return "no limit";
  return `${q.used} / ${q.limit} ${q.unit}`;
}

/** Frame total width clamped [60, 80]; falls back to 80 in non-TTY (piped/CI). */
const frameWidth = (terminalWidth?: number): number => {
  // Frame total width = inner content + 4. Inner clamped [60, 80].
  // When terminalWidth is out of range, add 2 for the frame border overhead.
  const inner = terminalWidth !== undefined
    ? Math.min(Math.max(terminalWidth, 60), 80)
    : process.stdout.isTTY
      ? Math.min(Math.max(process.stdout.columns ?? 80, 60), 80)
      : 80;
  const outOfRange = terminalWidth !== undefined && (terminalWidth < 60 || terminalWidth > 80);
  return inner + (outOfRange ? 2 : 4);
}

const padRight = (s: string, len: number): string => {
  return s.padEnd(len);
}

const padLeft = (s: string, len: number): string => {
  return s.padStart(len);
}

export class TableRenderer implements Renderer {
  render(quotas: readonly QuotaData[], ctx: RenderContext): string {
    const { t, color = undefined, compact = false, terminalWidth: tw, header: hdr } = ctx;
    const barOpts = ctx.progressBar ?? {};
    const w = frameWidth(tw);
    // inner width = frame width minus 4 ("| " and " |")
    const innerW = w - 4;

    // Frame borders
    const topBot = `+${"-".repeat(w - 2)}+`;

    // Header row: brand · plan · window info
    let headerRow = "";
    if (hdr) {
      const windowLabel = this._windowLabel(quotas[0]);
      const headerText = [hdr.brand, hdr.plan, windowLabel].filter(Boolean).join(" · ");
      headerRow = `| ${padRight(headerText, innerW)} |`;
    }

    const useColor = color !== undefined;
    const colorSplit: "filled" | "none" = useColor ? "filled" : "none";
    const barColorName = color;

    const rows = quotas.map(q => {
      const s = getStatus(q.used, q.limit);
      const statusCode = s.code;

      // Status column width is 4 chars (OK/WRN/ERR/UNK + trailing space)
      const statusCell = `${padRight(statusCode, 4)}`;
      // providerName cell
      const nameCell = `${padRight(q.providerName, 24)}`;
      // bar: tokens have no bar (text-only per design); % uses bar
      const showBar = q.unit !== "tokens";
      const barCell = showBar
        ? (useColor
            ? renderBar(s.ratio ?? 0, { ...barOpts, framed: true, colorName: barColorName, colorSplit, width: 10 })
            : renderBar(s.ratio ?? 0, { ...barOpts, framed: true, width: 10 }))
        : padRight("", 12); // 12-char placeholder for alignment when no bar
      // usage text cell
      const usageCell = padRight(usageText(q, s.ratio), 20);
      // reset cell
      const resetCell = padRight(fmtReset(q.reset), 6);
      // ettl cell (compact drops it)
      const ettlCell = compact ? "" : padRight(q.predictedReset ? fmtReset(q.predictedReset) : "—", 6);

      const rowText = `${statusCell} ${nameCell} ${barCell} ${usageCell} ${resetCell}${ettlCell}`;
      return `| ${padRight(rowText, innerW)} |`;
    });

    const lines = [topBot];
    if (headerRow) lines.push(headerRow);
    lines.push(...rows);
    lines.push(topBot);
    return lines.join("\n");
  }

  private _windowLabel(q: QuotaData | undefined): string {
    if (!q) return "";
    switch (q.window) {
      case "rolling-5h": return "rolling-5h";
      case "rolling-mcp": return "rolling-mcp";
      case "rolling-tokens": return "rolling-tokens";
      case "rolling-weekly": return "rolling-weekly";
      case "daily": return "daily";
      case "monthly": return "monthly";
      case "rolling": return "rolling";
      default: return "";
    }
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
  render(quotas: readonly QuotaData[], ctx: RenderContext): string {
    const rows = quotas.map(q => {
      const s = getStatus(q.used, q.limit);
      return `| ${q.providerName} | ${s.code} | ${fmtPct(s.ratio)} | ${fmtReset(q.reset)} | ${q.predictedReset ? fmtReset(q.predictedReset) : "—"} |`;
    });
    return [
      `| ${ctx.t.t("header.name")} | ${ctx.t.t("header.status")} | ${ctx.t.t("header.percent")} | ${ctx.t.t("header.reset")} | ${ctx.t.t("header.ettl")} |`,
      `|------|--------|-------|-------|-------|`,
      ...rows,
    ].join("\n");
  }
}
