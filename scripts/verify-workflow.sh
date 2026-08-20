#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Workflow verification failed: $1" >&2
  exit 1
}

test -f AGENTS.md || fail "AGENTS.md is missing"
test -f docs/workflow.md || fail "docs/workflow.md is missing"
test -f .claude/skills/taisa-workflow/SKILL.md || fail "Taisa workflow orchestrator is missing"
test -f docs/project-memory.md || fail "project memory index is missing"
test -f docs/decisions/README.md || fail "decision record guide is missing"
test -f docs/decisions/0001-use-repository-native-project-memory.md || fail "initial project memory decision is missing"
test -f docs/learnings.md || fail "reusable learning log is missing"
test "$(git remote get-url origin)" = "https://github.com/EmmanuelBaah27/taisa.git" || fail "origin does not use the canonical Taisa URL"

rg -q 'main.*only permanent branch|only permanent branch.*main' docs/workflow.md || fail "canonical main policy is missing"
rg -q '<type>/<short-kebab-case-description>' docs/workflow.md || fail "typed branch naming policy is missing"
rg -qi 'squash merge' docs/workflow.md || fail "squash merge policy is missing"
rg -q 'Ship approval|Ship gate' docs/workflow.md || fail "Ship authorization policy is missing"
rg -q 'superpowers:brainstorming' .claude/skills/taisa-workflow/SKILL.md || fail "brainstorming routing is missing"
rg -q 'superpowers:verification-before-completion' .claude/skills/taisa-workflow/SKILL.md || fail "completion verification routing is missing"
rg -q '\.claude/skills/taisa-workflow/SKILL\.md' AGENTS.md || fail "AGENTS.md does not load the orchestrator"
rg -q 'docs/workflow\.md' AGENTS.md || fail "AGENTS.md does not load the workflow source"
for startup_file in AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md; do
  rg -q 'docs/project-memory\.md' "$startup_file" || fail "$startup_file does not load the project memory index"
done
rg -q '^\*\*Status:\*\* Accepted$' docs/decisions/0001-use-repository-native-project-memory.md || fail "initial project memory decision is not accepted"
rg -q '^\| Date \| Area \| Learning \| Evidence \| Promoted to \|$' docs/learnings.md || fail "learning log table contract is missing"
rg -q 'Closeout' docs/workflow.md || fail "workflow closeout rule is missing"
rg -q 'memory-promotion check' docs/workflow.md || fail "workflow memory promotion rule is missing"
rg -q 'Closeout' .claude/skills/taisa-workflow/SKILL.md || fail "orchestrator closeout rule is missing"
rg -q 'memory-promotion check' .claude/skills/taisa-workflow/SKILL.md || fail "orchestrator memory promotion rule is missing"

verify_local_markdown_links() {
  local source target clean_target resolved

  for source in docs/project-memory.md docs/decisions/README.md docs/decisions/0001-use-repository-native-project-memory.md docs/learnings.md; do
    while IFS= read -r target; do
      case "$target" in
        http://*|https://*|mailto:*|\#*) continue ;;
      esac

      clean_target="${target%%#*}"
      clean_target="${clean_target%% *}"
      test -n "$clean_target" || continue
      resolved="$(dirname "$source")/$clean_target"
      test -e "$resolved" || fail "$source contains unresolved local link: $target"
    done < <(rg -o '\]\([^)]+\)' "$source" | sed -e 's/^](//' -e 's/)$//')
  done
}

verify_local_markdown_links

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
