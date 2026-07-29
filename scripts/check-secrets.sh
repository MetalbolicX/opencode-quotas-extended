#!/usr/bin/env bash
#
# scripts/check-secrets.sh
# Greps the production source tree for known secret patterns. Exits 0 if no
# secrets are found, non-zero otherwise. This is the gate that prevents
# hardcoded credentials from being committed.
#
# Scope: src/, scripts/, schemas/  (excludes node_modules, dist, coverage).
# Tests and fixtures are excluded by design: they intentionally contain
# non-secret placeholder values that exercise the scanner. A separate fixture
# review process protects committed fixtures.

set -euo pipefail

# Patterns we treat as credential material. Documented as tokens so they do
# not match the gate themselves; the actual literal characters live in PATTERN.
PATTERN='(GOCSPX[A-Za-z0-9_-]+|client_secret|clientSecret|'"s"'k-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]{16,})'

# Strings whose presence in a comment is benign — strip commented lines from
# the candidate matches before failing.
COMMENT_FILTER='^\s*(#|//|/\*|\*)'

found=0
for dir in src scripts schemas; do
  if [ -d "$dir" ]; then
    matches=$(grep -rEn "$PATTERN" "$dir" \
      --exclude-dir=node_modules \
      --exclude-dir=dist \
      --exclude-dir=coverage \
      2>/dev/null \
      | grep -vE "$COMMENT_FILTER" \
      | grep -v "^scripts/check-secrets.sh:" || true)
    if [ -n "$matches" ]; then
      echo "ERROR: Potential secret pattern detected in $dir/:"
      echo "$matches"
      found=1
    fi
  fi
done

if [ "$found" -ne 0 ]; then
  exit 1
fi

echo "[check-secrets] No secret patterns found in tracked source paths."
exit 0
