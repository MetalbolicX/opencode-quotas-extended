// I18n translator: pure function over a loaded catalog. I/O injected via loadCatalog.
import type { Translator } from "../ports/translator.js";
import en from "./locales/en.json";

export interface I18nTranslator extends Translator {
  readonly catalog: Record<string, string>;
}

// Replace {var} placeholders in template with values from vars.
const interpolate = (template: string, vars?: Record<string, string | number>): string => {
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? `{${k}}`));
}

export const createI18nTranslator = (catalog: Record<string, string>): I18nTranslator => ({
  catalog,
  t(key: string, vars?: Record<string, string | number>): string {
    const template = catalog[key];
    if (!template) return key; // missing key → return key (not undefined)
    return interpolate(template, vars);
  },
});

// Injectable catalog loader for testability.
// Uses static imports so the bundler includes locale JSON files in dist/.
const CATALOGS: Record<string, Record<string, string>> = {
  en: en as Record<string, string>,
};

export const loadCatalog = async (locale: string): Promise<Record<string, string>> => {
  const catalog = CATALOGS[locale];
  if (!catalog) throw new Error(`Unknown locale: ${locale}`);
  return catalog;
}
