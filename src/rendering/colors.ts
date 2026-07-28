// ANSI color name system — maps 16 standard color names to SGR codes.
// Used by renderBar() to apply color to the usage progress bar.

export const COLOR_MAP: Readonly<Record<string, string>> = Object.freeze({
  black: "30", red: "31", green: "32", yellow: "33",
  blue: "34", magenta: "35", cyan: "36", white: "37",
  brightBlack: "90", brightRed: "91", brightGreen: "92",
  brightYellow: "93", brightBlue: "94", brightMagenta: "95",
  brightCyan: "96", brightWhite: "97",
});

export function isValidColor(name: string): boolean {
  return Object.prototype.hasOwnProperty.call(COLOR_MAP, name);
}

export function ansiColor(name: string, text: string): string {
  const code = COLOR_MAP[name];
  if (!code) {
    throw new Error(
      `Invalid color name: "${name}". Valid: ${Object.keys(COLOR_MAP).join(", ")}`,
    );
  }
  return `\x1b[${code}m${text}\x1b[0m`;
}

export const DIM_SGR = "\x1b[2m";
export const RESET_SGR = "\x1b[0m";

export function dim(text: string): string {
  return `${DIM_SGR}${text}${RESET_SGR}`;
}
