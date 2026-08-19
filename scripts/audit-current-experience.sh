#!/usr/bin/env bash
set -euo pipefail

branches=(
  main
  docs/reimagine-product-scope
  feature/local-first-coaching-platform
  feature/chats
  feature/chat-input-states
  feature/design-system-evolution
  design-system
)

git status --short --branch
git worktree list --porcelain
git branch -avv

for branch in "${branches[@]}"; do
  printf '\nBRANCH %s\n' "$branch"
  git rev-parse "$branch"
  git merge-base main "$branch"
  git log --oneline "main..$branch"
done
