// auth-json-source: reads credentials from $XDG_DATA_HOME/opencode/auth.json (or default).
import type { Credential } from "../../ports/credentials.js";
import { getAuthJsonPath } from "../infra/paths.js";

interface AuthJsonEntry { type?: string; key?: string; access?: string; refresh?: string; expires?: number; token?: string; [k: string]: unknown; }
interface AuthJson { [p: string]: AuthJsonEntry; }

function parseEntry(e: AuthJsonEntry): Credential | null {
  if (e.type === "api" && typeof e.key === "string") return { variant: "api", key: e.key };
  if (e.type === "oauth" && typeof e.access === "string" && typeof e.refresh === "string") return { variant: "oauth", access: e.access, refresh: e.refresh, expires: e.expires ?? 0 };
  if (e.type === "wellknown" && typeof e.key === "string" && typeof e.token === "string") return { variant: "wellknown", key: e.key, token: e.token };
  return null;
}

export function createAuthJsonSource(
  fs: { readFileSync: (path: string) => string },
  env: Record<string, string | undefined> = process.env as Record<string, string | undefined>,
): (providerId: string) => Credential | null {
  return function get(providerId: string): Credential | null {
    try {
      const raw = JSON.parse(fs.readFileSync(getAuthJsonPath(env))) as AuthJson;
      const e = raw[providerId];
      return e ? parseEntry(e) : null;
    } catch { return null; }
  };
}
