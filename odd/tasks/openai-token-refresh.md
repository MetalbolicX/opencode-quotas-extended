# Feature: OpenAI OAuth token auto-refresh

> ODD feature document. Created before the first source write.

## Goal

Make the `openai` provider self-sustaining: refresh the ChatGPT OAuth access token
before expiry (or on 401) using the refresh token, and persist the rotated tokens
back to `~/.local/share/opencode/auth.json` — the same mechanism that keeps
opencode/pi logged in without manual `opencode auth login`.

## Decision (user-approved)

Full proactive refresh (option 1): proactive pre-expiry refresh + persist rotated
tokens + 401 fallback re-read/retry. Not the minimal 401-only re-read.

## Research evidence (pre-implementation)

- Memory 11712: 401 root cause — `Credential.OAuth` parses `refresh`/`expires`
  but `src/Providers/OpenAI.res` `fetchQuotasOAuth` sends `Bearer c.access`
  verbatim; no expiry check, no refresh, no retry. Legacy TS re-read+retry was
  also dropped in the port.
- `auth.json` openai entry shape: `{type:"oauth", access, refresh, expires, accountId}`;
  `expires` is a **millisecond epoch** (verified live: 1.79e12).
- Refresh endpoint + client id verified from local opencode bundle:
  `https://auth.openai.com/oauth/token`, client `app_EMoamEEZ73f0CkXaXp7hrann`,
  form-encoded `grant_type=refresh_token&refresh_token=...&client_id=...`.
- In-repo precedent for the refresh POST: `src/Providers/Gemini.res`
  `refreshAccessToken` (form-encoded, FetchHttp, redact:true). OpenAI differs:
  refresh tokens ROTATE → must persist back or the next refresh fails.
- `AuthJsonSource` reads via `Paths.getAuthJsonPath(~env=...)` (env-injectable,
  test-friendly); no write path exists yet.
- `src/Providers/CodingParse` precedent: sibling dir `CodingPlanParse/` next to
  `CodingPlanParse.res` works → `src/Providers/OpenAI/TokenRefresh.res` is a valid
  pure-submodule location (check `src/architecture/` scaffold guards).

## Design

- Pure (no I/O): `src/Providers/OpenAI/TokenRefresh.res`
  - `needsRefresh(expiresMs, nowMs)`: true only when `expiresMs > 0` and
    `now >= expiresMs - 60_000` (fixed 60s skew; expires=0 → not proactive, 401
    path covers it).
  - request builder (url, form params) + response parser → `{access, refresh?, expiresInS}`.
- Adapter: `AuthJsonSource.persistOAuthTokens(providerId, access, refresh, expiresMs)`
  — read-modify-write preserving `accountId` + all other entries, atomic write
  (temp + rename), env-injectable path for tests.
- Wiring: `fetchQuotasOAuth` — single-flight proactive refresh before WHAM; then:
  - FetchHttp has NO typed status (rejects with message `HTTP <status>: <url>`),
    so 401 detection matches that message.
  - On 401: re-read credential via injected hook; if access changed → retry once
    with the new token; if unchanged and not refreshed yet and refresh token
    exists → force refresh + persist + retry once; final 401 → reject (provider
    failures-reject invariant).
  - Re-read + persist are injected hooks (default: AuthJsonSource; tests pass
    stubs) so provider tests never touch the filesystem.

## Tasks

- [x] T1. Pure `TokenRefresh` module + tests (test-first RED→GREEN) (6d023d9).
- [x] T2. `AuthJsonSource.persistOAuthTokens` + tests (test-first RED→GREEN; merge
      preserves unrelated entries and accountId; atomic write; env path) (ae0cb59).
- [ ] T3. Wire into `OpenAI.fetchQuotasOAuth` (proactive + single-flight + 401
      re-read/retry) + `OpenAITests.res` fake-http tests (fresh token → no refresh;
      expiring → refresh+persist; refresh fail → 401 surfaces; 401 → re-read retry).
- [x] T4. README/CLAUDE.md behavior notes; all five gates green (verified by
      gentle-ai-verify on d3ce5f6: res:build, test 56 files, build, smoke, secrets).

## Evidence log

| Commit | Scope |
|---|---|
| 6d023d9 | T1 — pure OpenAI token-refresh helpers + tests (RED→GREEN) |
| ae0cb59 | T2 — atomic auth.json OAuth persistence + tests (RED→GREEN) |
| d3ce5f6 | T3 — proactive single-flight refresh + 401 recovery + fake-http tests |
| (this) | T4 — README/CLAUDE.md notes + feature-doc close |

## Verification

All five gates PASS on d3ce5f6 (gentle-ai-verify, 2026-10-09): `pnpm res:build`,
`pnpm test` (56 files), `pnpm build`, `node dist/cli/index.js --help`,
`bash scripts/check-secrets.sh`. Runtime refresh against the live endpoint not
exercised (no expired token available); covered by fake-http tests.

## Native review receipt (approved)

- Lineage `review-8b0652d9db4f4f74` · target `sha256:642b91bc…` · tier **high**
  (auth surface: `src/Auth/AuthJsonSource.res`) · 4 lenses · 16 files · 692 lines.
- Outcome: **approved**, zero blocking findings, zero corrections. Acknowledged
  and burned: `gentle-ai.review-acknowledged/v1`, consumed revision
  `sha256:9468ebad…`.
- Advisory (non-blocking, later work): R1-001 risk AuthJsonSource.res:50 ·
  R1-002 risk OpenAI.res:59 · R2-001 readability odd doc:57 · R3-001/002
  reliability OpenAI.res:34/51 · R4-001 resilience OpenAI.res:59.
