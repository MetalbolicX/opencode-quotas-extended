# Anthropic Admin Scope — Blocked Live Capture

## Constraint

The Anthropic admin usage endpoint (`/v1/organizations/{org_id}/usage`) requires an API key with the **Admin API** organization usage read permission (`usage:read`). Standard API keys (without admin scope) receive **401/403** and the adapter throws a clear actionable error:

> "Anthropic admin-usage request denied (401/403). Confirm your API key has the 'Admin API' organization usage read permission."

This is not a code limitation — it is a permission constraint imposed by Anthropic's API.

## Impact on Fixture

The fixture files under `tests/fixtures/providers/anthropic/` (`usage.json`, `usage-page-2.json`, `usage-page-2-terminal.json`) are constructed from the **documented API response shape** (not a live capture). They are marked **validation-pending** because:

- A live response has not been captured with an admin-scoped credential.
- The exact field names, nesting, and types are inferred from Anthropic's API documentation.
- The response shape (`data[].usage.input_tokens`, `data[].model`, `data[].time_bucket`, `has_more`, `next_page`) is plausible but unverified against live data.

## How to Enable Live Capture

1. Obtain an Anthropic API key with **Admin API** organization permissions.
2. Set the key in `auth.json.anthropic` or `ANTHROPIC_API_KEY` env var.
3. Set `anthropic.orgId` in `quotas.json` or `auth.json.anthropic.orgId`.
4. Run the CLI once with `--dry-run` or inspect the raw HTTP response.
5. Replace `tests/fixtures/providers/anthropic/usage.json` with the live captured, redacted response.
6. Re-run `bash scripts/check-secrets.sh` to confirm redaction.
7. Update this README to remove "validation-pending".

## Redaction Protocol

Before committing any live-captured fixture:
```bash
# Recursively replace key patterns with ****
jq 'walk(if type == "object" then with_entries(
  if .key | test("^(key|access|refresh|token|api.?key|token.?id)$"; "i")
  then .value = "****"
  else .
  end
) else . end)' live-usage.json > tests/fixtures/providers/anthropic/usage.json

# Verify check-secrets.sh passes
bash scripts/check-secrets.sh
```

## Failure Modes

| Status | Meaning | Adapter Behavior |
|--------|---------|-----------------|
| 401 | API key lacks `usage:read` scope | Throws actionable error |
| 403 | Organization restricts admin API access | Throws actionable error |
| 404 | Organization ID not found | Throws (not silent `[]`) |
| 200 + empty `data` | No usage data for this period | Returns `[]` — correct, not an error |
