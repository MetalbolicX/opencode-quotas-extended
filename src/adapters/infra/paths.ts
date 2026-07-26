// XDG-aware path resolution for opencode data files.
import { homedir } from "node:os";
import { join } from "node:path";

function getDataHome(env: Record<string, string | undefined> = process.env as Record<string, string | undefined>): string | undefined {
  return env["XDG_DATA_HOME"];
}

export function getAuthJsonPath(env?: Record<string, string | undefined>): string {
  const xdg = getDataHome(env);
  if (xdg) return join(xdg, "opencode", "auth.json");
  return join(homedir(), ".local", "share", "opencode", "auth.json");
}

export function getHistoryPath(env?: Record<string, string | undefined>): string {
  const xdg = getDataHome(env);
  if (xdg) return join(xdg, "opencode", "quota-history.json");
  return join(homedir(), ".local", "share", "opencode", "quota-history.json");
}
