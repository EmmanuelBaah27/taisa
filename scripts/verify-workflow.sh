#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Workflow verification failed: $1" >&2
  exit 1
}

test -f AGENTS.md || fail "AGENTS.md is missing"
test -f docs/workflow.md || fail "docs/workflow.md is missing"
test -f .claude/skills/taisa-workflow/SKILL.md || fail "Taisa workflow orchestrator is missing"
test "$(git remote get-url origin)" = "https://github.com/EmmanuelBaah27/taisa.git" || fail "origin does not use the canonical Taisa URL"

rg -q 'main.*only permanent branch|only permanent branch.*main' docs/workflow.md || fail "canonical main policy is missing"
rg -q '<type>/<short-kebab-case-description>' docs/workflow.md || fail "typed branch naming policy is missing"
rg -qi 'squash merge' docs/workflow.md || fail "squash merge policy is missing"
rg -q 'Ship approval|Ship gate' docs/workflow.md || fail "Ship authorization policy is missing"
rg -q 'superpowers:brainstorming' .claude/skills/taisa-workflow/SKILL.md || fail "brainstorming routing is missing"
rg -q 'superpowers:verification-before-completion' .claude/skills/taisa-workflow/SKILL.md || fail "completion verification routing is missing"
rg -q '\.claude/skills/taisa-workflow/SKILL\.md' AGENTS.md || fail "AGENTS.md does not load the orchestrator"
rg -q 'docs/workflow\.md' AGENTS.md || fail "AGENTS.md does not load the workflow source"

if rg -n 'One branch per feature: `feature/<name>`' CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md; then
  fail "legacy feature-only branch rule remains"
fi

old_repo_slug='taisa'"-os"
old_workspace_name='Taisa'"-OS"
old_repo_path="EmmanuelBaah27/${old_repo_slug}"
stale_refs="$({ git grep -n -I -e "$old_repo_slug" -e "$old_workspace_name" -e "$old_repo_path" -- . \
  ':!docs/superpowers/specs/2026-08-09-rename-project-taisa-design.md' \
  ':!docs/superpowers/plans/2026-08-09-rename-project-taisa.md' || true; })"
test -z "$stale_refs" || {
  printf '%s\n' "$stale_refs" >&2
  fail "stale Taisa repository references remain"
}

echo 'Workflow verification passed.'
