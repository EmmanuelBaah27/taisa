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
node scripts/canonical-origin.mjs "$(git remote get-url origin)" || fail "origin does not use the canonical Taisa URL"

# Linear is the sole live delivery authority. These checks intentionally stay
# offline: they verify repository contracts without reading or mutating Linear.
test ! -e docs/roadmap.md || fail "repository roadmap duplicates Linear live authority"

for authority_file in AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md; do
  rg -qi 'Linear.*sole live authority|sole live authority.*Linear' "$authority_file" ||
    fail "$authority_file does not declare Linear as the sole live authority"
  rg -qi 'Linear.*unavailable|offline fallback' "$authority_file" ||
    fail "$authority_file is missing the Linear-unavailable fallback"
done

if rg -n 'Active Work table|docs/roadmap\.md' \
  AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md docs/project-memory.md; then
  fail "active repository instructions still reference duplicate live authority"
fi

if rg -n 'No formal Work Map, scope doc, or Linear issue|No Linear issue|Linear issues are created only' \
  AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md docs/project-memory.md; then
  fail "active repository instructions still permit actionable work without Linear intake"
fi

rg -q '31b0d99c-6f74-4c9c-af2a-12e6e25aabe0' \
  .claude/skills/taisa-workflow/SKILL.md || fail "Taisa Linear project ID is missing"
rg -q 'e95356d8-17f7-4700-bdfe-222782bea546' \
  .claude/skills/taisa-workflow/SKILL.md || fail "Taisa Linear team ID is missing"
rg -qi 'every actionable task.*Linear issue|Linear issue.*every actionable task' \
  .claude/skills/taisa-workflow/SKILL.md || fail "universal Linear issue intake is missing"

rg -q 'main.*only permanent branch|only permanent branch.*main' docs/workflow.md || fail "canonical main policy is missing"
rg -q '<type>/<short-kebab-case-description>' docs/workflow.md || fail "typed branch naming policy is missing"
rg -qi 'squash merge' docs/workflow.md || fail "squash merge policy is missing"
rg -q 'Ship approval|Ship gate' docs/workflow.md || fail "Ship authorization policy is missing"
rg -q 'superpowers:brainstorming' .claude/skills/taisa-workflow/SKILL.md || fail "brainstorming routing is missing"
rg -q 'superpowers:verification-before-completion' .claude/skills/taisa-workflow/SKILL.md || fail "completion verification routing is missing"
rg -q '\.claude/skills/taisa-workflow/SKILL\.md' AGENTS.md || fail "AGENTS.md does not load the orchestrator"
rg -q 'docs/workflow\.md' AGENTS.md || fail "AGENTS.md does not load the workflow source"
rg -q '^### Work Map' docs/workflow.md || fail "pre-planning Work Map contract is missing"
rg -q '^### Discussion Map' docs/workflow.md || fail "selected-slice Discussion Map contract is missing"
rg -qi 'layman meaning.*technical truth' docs/workflow.md || fail "balanced architecture-diagram contract is missing"
rg -q 'Platform discussion' .claude/skills/taisa-workflow/SKILL.md || fail "Platform discussion agenda is missing"
rg -q 'Product discussion' .claude/skills/taisa-workflow/SKILL.md || fail "Product discussion agenda is missing"
rg -q 'Integration discussion' .claude/skills/taisa-workflow/SKILL.md || fail "integration discussion agenda is missing"
rg -q 'XS.*S.*M.*L.*XL' docs/workflow.md || fail "slice sizing scale is missing"
rg -q 'independent Product foundation' docs/workflow.md || fail "Product skeleton dependency boundary is missing"
rg -q '^### Activation bias' docs/workflow.md || fail "workflow activation bias is missing"
rg -qi 'default.*activat|activate.*default' .claude/skills/taisa-workflow/SKILL.md || fail "orchestrator does not default toward activation"
rg -q '^## Documentation freshness cadence' docs/workflow.md || fail "documentation freshness cadence is missing"
rg -q 'Explicit precedence|explicit precedence' docs/workflow.md || fail "activation precedence is missing"
rg -q 'between Scope and Plan' docs/workflow.md || fail "Product design boundary is missing"
rg -q 'host artifact' docs/workflow.md || fail "embedded diagram ownership is missing"
rg -q 'Canonical documentation authority' docs/workflow.md || fail "canonical documentation authority is missing"
rg -q 'Material change' docs/workflow.md || fail "material-change definition is missing"
rg -q 'Superseded by' docs/workflow.md || fail "superseded-document lifecycle is missing"
test -f scripts/verify-doc-freshness.sh || fail "documentation freshness verifier is missing"

if rg -n '^\| Backlog idea \| Create issue' .claude/skills/taisa-workflow/SKILL.md; then
  fail "backlog-to-Linear contradiction remains"
fi
for startup_file in AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md; do
  rg -q 'docs/project-memory\.md' "$startup_file" || fail "$startup_file does not load the project memory index"
done
rg -q '^\*\*Status:\*\* Accepted$' docs/decisions/0001-use-repository-native-project-memory.md || fail "initial project memory decision is not accepted"
rg -q '^\| Date \| Area \| Learning \| Evidence \| Promoted to \|$' docs/learnings.md || fail "learning log table contract is missing"
rg -q 'Closeout' docs/workflow.md || fail "workflow closeout rule is missing"
rg -q 'memory-promotion check' docs/workflow.md || fail "workflow memory promotion rule is missing"
rg -q 'Closeout' .claude/skills/taisa-workflow/SKILL.md || fail "orchestrator closeout rule is missing"
rg -q 'memory-promotion check' .claude/skills/taisa-workflow/SKILL.md || fail "orchestrator memory promotion rule is missing"
test -f .github/workflows/native-apple.yml || fail "native Apple CI workflow is missing"
rg -q 'npm run verify:native-apple:all' .github/workflows/native-apple.yml || fail "CI does not enforce complete native Apple verification"

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
  ':!docs/migration/swiftui/baseline-manifest.json' \
  ':!docs/superpowers/specs/2026-08-09-rename-project-taisa-design.md' \
  ':!docs/superpowers/plans/2026-08-09-rename-project-taisa.md' || true; })"
test -z "$stale_refs" || {
  printf '%s\n' "$stale_refs" >&2
  fail "stale Taisa repository references remain"
}

echo 'Workflow verification passed.'
