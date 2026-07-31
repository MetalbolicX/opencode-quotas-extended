// I18n translator: pure function over a loaded catalog.

// Generated catalog module (produced by scripts/codegen.mjs)
// EnCatalog.res lives in src/i18n/Translator/ (subdirectory of Translator),
// making it accessible as EnCatalog (a submodule of Translator).

type translator = {
  t: (string, option<dict<string>>) => string,
}

// Replace {var} placeholders in template with values from vars.
let interpolate = (template: string, ~vars: option<dict<string>>): string => {
  switch vars {
  | None => template
  | Some(v) =>
    // Split by {var} pattern and reassemble with values
    let parts = String.split(template, "{")
    let result = ref("")
    parts->Belt.Array.forEachWithIndex((i, part) => {
      if i === 0 {
        result := part
      } else {
        let closingIdx = String.indexOf(part, "}")
        if closingIdx === -1 {
          result := result.contents ++ "{" ++ part
        } else {
          let key = String.substring(part, ~start=0, ~end=closingIdx)
          let rest = String.substring(part, ~start=closingIdx + 1, ~end=String.length(part))
          let replacement = switch Dict.get(v, key) {
          | Some(val') => val'
          | None => `{${key}}`
          }
          result := result.contents ++ replacement ++ rest
        }
      }
    })
    result.contents
  }
}

let createI18nTranslator = (catalog: dict<string>): translator => {
  {
    t: (key, vars) => {
      switch Dict.get(catalog, key) {
      | Some(template) => interpolate(template, ~vars)
      | None => key // missing key → return key (not undefined)
      }
    }
  }
}

// enCatalog is imported from EnCatalog submodule (produced by scripts/codegen.mjs)
let enCatalog: dict<string> = EnCatalog.enCatalog
