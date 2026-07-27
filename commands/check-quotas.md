---
description: Show quota usage for configured AI providers with a manual picker.
agent: build
model: default
---

This command shows the AI provider quota usage through a manual picker. The CLI is the source of truth; this body selects which CLI invocation to run based on whether the user passed an argument.

If the user typed /check-quotas with no argument:
1. Run opencode-quotas --no-color --list to get a numbered list of available providers (one per line, with their IDs).
2. Render the list as a fenced text block so the user sees the picker.
3. Ask the user: "¿Querés ver el detalle de alguno? Respondé con el número o ID (o 'all' para mantener esta vista)."

If the user typed /check-quotas <id> (a provider number or ID):
- Run opencode-quotas --no-color --provider "$ARGUMENTS" and render the resulting report.

Safety: $ARGUMENTS is interpolated by opencode at parse time and only ever flows into the --provider flag value, which the CLI validates against the provider registry before any HTTP call. Unknown IDs exit 1 with a clear error.
