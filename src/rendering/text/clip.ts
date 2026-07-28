// ANSI-aware text clip: scans value preserving ANSI SGR codes,
// truncates to (width - ellipsis.length) visible chars, pads to width.
const SGR_RE = /\x1b\[[0-9;]*m/g;

export function stripAnsi(text: string): string {
  return text.replace(SGR_RE, "");
}

/**
 * Clip `value` to `width` visible characters.
 * - Scans value; SGR sequences are preserved and attached to the next visible char.
 * - Truncates at (width - ellipsis.length) visible chars, appends ellipsis.
 * - If visible length <= width: returns stripped+padded text (ANSI dropped).
 */
export function clip(value: string, width: number, ellipsis = "…"): string {
  if (width <= 0) return "";
  if (ellipsis.length >= width) return ellipsis.slice(0, width);

  const visibleLen = stripAnsi(value).length;

  // No truncation needed
  if (visibleLen <= width) {
    return stripAnsi(value).padEnd(width);
  }

  // Truncation case: keep (width - ellipsis.length) visible chars
  const targetVisible = width - ellipsis.length;
  let result = "";
  let visCount = 0;
  let i = 0;
  let pendingSgr = "";

  while (i < value.length && visCount < targetVisible) {
    if (value[i] === "\x1b" && value[i + 1] === "[") {
      const end = value.indexOf("m", i);
      if (end === -1) break;
      pendingSgr = value.slice(i, end + 1);
      i = end + 1;
      continue;
    }
    if (pendingSgr) {
      result += pendingSgr;
      pendingSgr = "";
    }
    result += value[i];
    visCount++;
    i++;
  }

  result += ellipsis;
  return result;
}
