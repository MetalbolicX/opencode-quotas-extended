# Gemini Antigravity Fixtures — Validation Pending

## Overview

This directory contains synthetic/redacted fixtures for the Gemini Antigravity quota adapter.
These fixtures are used for unit testing only — no live credentials are present.

## Fixture Files

### antigravity-models.json
Mocked `fetchAvailableModels` response from `POST https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`.

Shape:
```json
{
  "models": {
    "<model-name>": {
      "quotaInfo": {
        "remainingFraction": 0.0-1.0,
        "resetTime": "ISO-8601 string"
      }
    }
  }
}
```

Tracked models: `gemini-3-pro-high`, `gemini-3-pro-low`, `gemini-3-flash`, `gemini-3-pro-image`.
Other models in response are skipped silently.

### oauth-token-response.json
Mocked OAuth refresh response from `POST https://oauth2.googleapis.com/token`.

## Enabling Live Capture

To capture real fixtures:

1. Ensure `~/.config/opencode/antigravity-accounts.json` is present with valid credentials
2. Run the provider in a test environment with network access
3. Capture the raw response and redact using:
   ```bash
   jq 'walk(if type == "object" then with_entries(select(.key | test("access|refresh|token|client_secret|id_token"; "i")) | .value = "****") else . end)' < raw.json > fixtures/providers/gemini/antigravity-models.json
   ```

## Validation

All fixtures pass `scripts/check-secrets.sh` — no real secrets are present.
