// I18n translator: pure function over a loaded catalog. I/O injected via loadCatalog.
import type { Translator } from "../ports/translator.js";

export interface I18nTranslator extends Translator {
  readonly catalog: Record<string, string>;
}

// Replace {var} placeholders in template with values from vars.
function interpolate(template: string, vars?: Record<string, string | number>): string {
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? `{${k}}`));
}

export function createI18nTranslator(catalog: Record<string, string>): I18nTranslator {
  return {
    catalog,
    t(key: string, vars?: Record<string, string | number>): string {
      const template = catalog[key];
      if (!template) return key; // missing key → return key (not undefined)
      return interpolate(template, vars);
    },
  };
}

// Injectable catalog loader for testability.
export async function loadCatalog(locale: string): Promise<Record<string, string>> {
  // Dynamic import of the locale JSON — bundler resolves this at build time.
  const mod = await import(`./locales/${locale}.json`);
  return mod.default as Record<string, string>;
}
