#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Documentation freshness verification failed: $1" >&2
  exit 1
}

test "$#" -gt 0 || fail "provide at least one documentation path"
today="$(date +%F)"

for document in "$@"; do
  test -f "$document" || fail "$document is missing"
  git ls-files --error-unmatch "$document" >/dev/null 2>&1 || fail "$document is not tracked"
  test -s "$document" || fail "$document is empty"
  rg -q '^# ' "$document" || fail "$document has no top-level heading"
  updated="$(sed -nE 's/^\*\*Last updated:\*\* ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$document" | head -1)"
  test -n "$updated" || fail "$document has no ISO Last updated field"
  [[ "$updated" > "$today" ]] && fail "$document has a future Last updated date"
  if rg -q '^(<<<<<<<|=======|>>>>>>>)' "$document"; then
    fail "$document contains an unresolved merge marker"
  fi
done

echo "Documentation freshness verification passed for $# files."
