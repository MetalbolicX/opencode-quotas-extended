// I18n translator: pure function over a loaded catalog.

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

// Embedded English catalog (en.json)
let enCatalog: dict<string> = Dict.fromArray([
  ("status.OK", "OK"),
  ("status.WRN", "WRN"),
  ("status.ERR", "ERR"),
  ("status.UNK", "UNK"),
  ("header.name", "Name"),
  ("header.used", "Used"),
  ("header.limit", "Limit"),
  ("header.bar", "Bar"),
  ("header.percent", "%"),
  ("header.reset", "Reset"),
  ("header.ettl", "ETTL"),
  ("header.status", "Status"),
  ("footer.compact", "Compact quota summary"),
  ("unit.req", "req"),
  ("unit.credits", "credits"),
  ("unit.calls", "calls"),
  ("unit.%", "%"),
  ("concept.z.ai-5-hour-rolling", "5h rolling window"),
  ("concept.z.ai-mcp", "MCP quota"),
  ("concept.z.ai-token", "Token quota"),
  ("concept.minimax-daily-request", "Daily request quota"),
  ("concept.minimax-weekly-request", "Weekly limit"),
  ("concept.minimax-5h-window", "5h rolling limit"),
  ("concept.minimax-video", "Video generation"),
  ("concept.z.ai-weekly-rolling", "Weekly quota"),
  ("concept.z.ai-generic-rolling", "Generic rolling limit"),
  ("concept.openai-primary-rate", "Primary rate limit"),
  ("concept.openai-secondary-rate", "Secondary rate limit"),
  ("concept.openai-credits", "Credit balance"),
  ("concept.openai-token-usage", "Token usage"),
  ("concept.gemini-model-quota", "Model quota"),
])
