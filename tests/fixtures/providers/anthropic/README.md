# Anthropic Admin Usage Fixture — Validation Pending

**Status**: `validation-pending`

**Reason**: Live capture pending admin-scope API credential.

The fixture files in this directory are constructed from the documented Anthropic admin usage API response shape, not from a live HTTP response captured with a valid admin-scoped API key.

## Fixture Files

| File | Purpose |
|------|---------|
| `usage.json` | Single-page response: one usage entry, `has_more: false` |
| `usage-page-2.json` | First page of a 2-page response: `has_more: true`, `next_page: "cursor_page_2"` |
| `usage-page-2-terminal.json` | Terminal page of the 2-page sequence: `has_more: false` |

## Response Shape (Documented, Unverified)

```json
{
  "data": [
    {
      "usage": { "input_tokens": 1000, "output_tokens": 500, "total_tokens": 1500 },
      "model": "claude-3-5-sonnet-20250620",
      "workspace_id": "ws_****",
      "time_bucket": "2026-07-26T00:00:00Z"
    }
  ],
  "has_more": false,
  "next_page": null
}
```

Field semantics:
- `data[].usage.input_tokens` / `output_tokens`: token counts for the period
- `data[].model`: model identifier
- `data[].workspace_id`: workspace (redacted in fixture)
- `data[].time_bucket`: ISO timestamp granularity
- `has_more` + `next_page`: cursor pagination (up to 20 pages)

## Validation Steps

1. Obtain an admin-scoped Anthropic API key.
2. Capture a live response via `curl` or the CLI in debug mode.
3. Compare the live shape against this documented shape.
4. Update field names / nesting if the live API differs.
5. Apply redaction protocol (see `notes/anthropic-admin-scope-blocked.md`).
6. Remove "validation-pending" from this README.

## Adapter Mapping

The adapter (`src/adapters/providers/anthropic.ts`) maps:
- `input_tokens + output_tokens` → `used` (tokens, summed)
- `model` → `providerName` (`Anthropic {model}`)
- `time_bucket` prefix `YYYY-MM-DD` → `window: "daily"`; otherwise `"rolling"`
- `limit: null` (no cap in admin API response)
- `info: "Anthropic {model} ({time_bucket})"`
