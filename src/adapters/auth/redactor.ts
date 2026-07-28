// Redactor: recursive **** redaction for sensitive keys.
const REDACT_KEYS = new Set(["key", "access", "refresh", "token", "apiKey", "password", "secret"]);

// Mask: sk- style → 4 visible chars + ****; others → 3 visible + ****
const mask = (val: string): string => {
  const isSk = val.startsWith("sk-");
  const prefix = isSk ? 4 : 3;
  const p = val.slice(0, Math.min(prefix, val.length));
  return p + "****";
};

export const redact = <T>(obj: T): T => {
  if (obj === null || obj === undefined) return obj;
  if (typeof obj !== "object") return obj;
  if (Array.isArray(obj)) return obj.map((v) => redact(v)) as T;
  const result: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    if (REDACT_KEYS.has(k) && typeof v === "string") {
      result[k] = mask(v);
    } else if (typeof v === "object") {
      result[k] = redact(v);
    } else {
      result[k] = v;
    }
  }
  return result as T;
}
