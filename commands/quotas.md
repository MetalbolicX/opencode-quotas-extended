---
description: Show quota usage and predictions for configured AI providers.
agent: build
model: default
---

Render a quota status report for all configured providers using the shared pipeline.

The report is printed as a fenced text block and respects the displayMode, progressBar, table, footer, disabled, aggregatedGroups, historyMaxAgeHours, pollingInterval, predictionWindowMinutes, predictionShortWindowMinutes, showUnaggregated, and filterByCurrentModel settings from .opencode/quotas.json (if present).

This command invokes the fixed CLI with --no-color to ensure deterministic, ANSI-free output regardless of terminal settings:

opencode-quotas --no-color
