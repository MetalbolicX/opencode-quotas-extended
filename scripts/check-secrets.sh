#!/usr/bin/env bash
#
# scripts/check-secrets.sh
# Greps src/ for known secret patterns. Exits 0 if no secrets found, non-zero otherwise.
# This is the CI gate that prevents hardcoded credentials from being committed.
#

set -euo pipefail

PATTERN='GOCSPX|client_secret|clientSecret|sk-[a-zA-Z0-9]{20,}'

# Only scan the src/ directory
if [ -d "src" ]; then
  matches=$(grep -rE "$PATTERN" src/ --exclude-dir=node_modules 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "ERROR: Potential secret pattern detected in src/:"
    echo "$matches"
    exit 1
  fi
fi

echo "[check-secrets] No secret patterns found in src/"
exit 0
