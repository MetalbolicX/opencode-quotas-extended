// WU-2: pure semantic label helpers for quota enrichment.
// Adapters own label resolution; renderer treats info as opaque.

type quotaConcept =
  | @as("z.ai-5-hour-rolling") ZAi5HourRolling
  | @as("z.ai-mcp") ZAiMcp
  | @as("z.ai-token") ZAiToken
  | @as("minimax-daily-request") MinimaxDailyRequest
  | @as("minimax-weekly-request") MinimaxWeeklyRequest
  | @as("minimax-5h-window") Minimax5hWindow
  | @as("minimax-video") MinimaxVideo
  | @as("z.ai-weekly-rolling") ZAiWeeklyRolling
  | @as("z.ai-generic-rolling") ZAiGenericRolling
  | @as("openai-primary-rate") OpenaiPrimaryRate
  | @as("openai-secondary-rate") OpenaiSecondaryRate
  | @as("openai-credits") OpenaiCredits
  | @as("openai-token-usage") OpenaiTokenUsage
  | @as("gemini-model-quota") GeminiModelQuota
  | @as("kimi-weekly-usage") KimiWeeklyUsage
  | @as("kimi-5h-rolling") Kimi5hRolling

type providerPayloadHints = {
  type_: option<string>,
  unit: option<string>,
  number: option<float>,
  modelName: option<string>,
  weekly: option<bool>,
  openaiVariant: option<string>,
  geminiModel: option<string>,
}

type enrichedLabel = {
  label: string,
  concept: quotaConcept,
}

let labelMap: dict<string> = Dict.fromArray([
  ("z.ai-5-hour-rolling", "5h rolling window"),
  ("z.ai-mcp", "MCP quota"),
  ("z.ai-token", "Token quota"),
  ("minimax-daily-request", "Daily request quota"),
  ("minimax-weekly-request", "Weekly limit"),
  ("minimax-5h-window", "5h rolling limit"),
  ("minimax-video", "Video generation"),
  ("z.ai-weekly-rolling", "Weekly limit"),
  ("z.ai-generic-rolling", "Generic rolling limit"),
  ("openai-primary-rate", "5h rolling window"),
  ("openai-secondary-rate", "Weekly limit"),
  ("openai-credits", "Credit balance"),
  ("openai-token-usage", "Token usage"),
  ("gemini-model-quota", "Model quota"),
  ("kimi-weekly-usage", "Kimi weekly usage"),
  ("kimi-5h-rolling", "Kimi 5h rolling limit"),
])

let getLabel = (concept: string): string => {
  switch Dict.get(labelMap, concept) {
  | Some(label) => label
  | None => ""
  }
}



let enrichQuotaLabel = (_providerId: string, hints: providerPayloadHints): enrichedLabel => {
  let type_ = hints.type_
  let unit = hints.unit
  let number = hints.number
  let modelName = hints.modelName
  let weekly = hints.weekly
  let openaiVariant = hints.openaiVariant
  let geminiModel = hints.geminiModel

  // kimi concepts — use providerId guard; weekly hint distinguishes weekly vs 5h
  switch _providerId {
  | "kimi" =>
    switch weekly {
    | Some(true) => {label: getLabel("kimi-weekly-usage"), concept: KimiWeeklyUsage}
    | Some(false) | None => {label: getLabel("kimi-5h-rolling"), concept: Kimi5hRolling}
    }
  | _ => {
    // z.ai TIME_LIMIT — unit branching
    switch type_ {
    | Some("TIME_LIMIT") =>
      switch unit {
      | Some("5") => {label: getLabel("z.ai-5-hour-rolling"), concept: ZAi5HourRolling}
      | Some("weekly") => {label: getLabel("z.ai-weekly-rolling"), concept: ZAiWeeklyRolling}
      | Some(u) =>
        let unitVal = Float.fromString(u)
        switch unitVal {
        | Some(v) if v >= 168.0 => {label: getLabel("z.ai-weekly-rolling"), concept: ZAiWeeklyRolling}
        | _ =>
          let concept: quotaConcept = ZAiGenericRolling
          let label = `${u}-hour rolling limit`
          {label, concept}
        }
      | None =>
        let concept: quotaConcept = ZAiGenericRolling
        let label = "?-hour rolling limit"
        {label, concept}
      }
    | Some("MCP_LIMIT") => {label: getLabel("z.ai-mcp"), concept: ZAiMcp}
    | Some("TOKENS_LIMIT") =>
      let base = getLabel("z.ai-token")
      let discriminator = switch number {
      | Some(n) => ` #${Belt.Float.toString(n)}`
      | None => ""
      }
      {label: `${base}${discriminator}`, concept: ZAiToken}
    | _ =>
      // minimax concepts — weekly wins
      switch weekly {
      | Some(true) => {label: getLabel("minimax-weekly-request"), concept: MinimaxWeeklyRequest}
      | _ =>
        switch modelName {
        | Some("general") => {label: getLabel("minimax-5h-window"), concept: Minimax5hWindow}
        | Some("video") => {label: getLabel("minimax-video"), concept: MinimaxVideo}
        | Some(_) => {label: getLabel("minimax-daily-request"), concept: MinimaxDailyRequest}
        | None =>
          switch openaiVariant {
          | Some("primary") => {label: getLabel("openai-primary-rate"), concept: OpenaiPrimaryRate}
          | Some("secondary") => {
              label: getLabel("openai-secondary-rate"),
              concept: OpenaiSecondaryRate,
            }
          | Some("credits") => {label: getLabel("openai-credits"), concept: OpenaiCredits}
          | Some("api") => {label: getLabel("openai-token-usage"), concept: OpenaiTokenUsage}
          | Some(_) | None =>
            switch geminiModel {
            | Some(_) => {label: getLabel("gemini-model-quota"), concept: GeminiModelQuota}
            | None => // Fallback — return token usage concept to avoid empty strings
              {label: getLabel("openai-token-usage"), concept: OpenaiTokenUsage}
            }
          }
        }
      }
    }
    }
  }
}

let buildProviderName = (
  brand: string,
  concept: quotaConcept,
  ~model: option<string>=?,
  ~labelOverride: option<string>=?,
): string => {
  let conceptStr = switch concept {
  | ZAi5HourRolling => "z.ai-5-hour-rolling"
  | ZAiMcp => "z.ai-mcp"
  | ZAiToken => "z.ai-token"
  | MinimaxDailyRequest => "minimax-daily-request"
  | MinimaxWeeklyRequest => "minimax-weekly-request"
  | Minimax5hWindow => "minimax-5h-window"
  | MinimaxVideo => "minimax-video"
  | ZAiWeeklyRolling => "z.ai-weekly-rolling"
  | ZAiGenericRolling => "z.ai-generic-rolling"
  | OpenaiPrimaryRate => "openai-primary-rate"
  | OpenaiSecondaryRate => "openai-secondary-rate"
  | OpenaiCredits => "openai-credits"
  | OpenaiTokenUsage => "openai-token-usage"
  | GeminiModelQuota => "gemini-model-quota"
  | KimiWeeklyUsage => "kimi-weekly-usage"
  | Kimi5hRolling => "kimi-5h-rolling"
  }
  let label = switch labelOverride {
  | Some(ov) => ov
  | None => getLabel(conceptStr)
  }
  switch concept {
  | GeminiModelQuota =>
    switch model {
    | Some(m) => `${brand}\u00A0·\u00A0${label} (${m})`
    | None => `${brand}\u00A0·\u00A0${label}`
    }
  | _ => `${brand}\u00A0·\u00A0${label}`
  }
}
