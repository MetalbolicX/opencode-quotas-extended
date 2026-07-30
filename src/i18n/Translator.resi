// I18n translator - pure function over a loaded catalog.

type translator = {
  t: (string, option<dict<string>>) => string,
}

let createI18nTranslator: dict<string> => translator
let enCatalog: dict<string>
