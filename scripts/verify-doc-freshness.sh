#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Documentation freshness verification failed: $1" >&2
  exit 1
}

test "$#" -gt 0 || fail "provide at least one affected Work Map, scope, handoff, or plan"

for artifact in "$@"; do
  test -f "$artifact" || fail "$artifact does not exist"
  rg -q '^\*\*Status:\*\*[[:space:]]+[^[:space:]].*$' "$artifact" ||
    fail "$artifact is missing a populated **Status:** field"
  rg -q '^\*\*Last updated:\*\*[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' "$artifact" ||
    fail "$artifact is missing **Last updated:** in YYYY-MM-DD format"
  if rg -q '^\*\*Last updated:\*\*[[:space:]]+YYYY-MM-DD[[:space:]]*$' "$artifact"; then
    fail "$artifact still contains the Last updated placeholder"
  fi
done

echo "Documentation freshness verification passed for $# artifact(s)."
