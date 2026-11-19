#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Workflow verification failed: $1" >&2
  exit 1
}

required_files=(
  AGENTS.md
  CLAUDE.md
  docs/workflow.md
  docs/project-memory.md
  docs/agents/issue-tracker.md
  .agents/skills/taisa-workflow/SKILL.md
  .agents/skills/taisa-workflow/templates/bounded-goal.md
)

for file in "${required_files[@]}"; do
  test -e "$file" || fail "$file is missing"
done

node scripts/canonical-origin.mjs "$(git remote get-url origin)" ||
  fail "origin does not use the canonical Taisa URL"

test_suites=(
  scripts/__tests__/matt-workflow-routing.test.mjs
  scripts/__tests__/tracer-delivery.test.mjs
  scripts/__tests__/authority-routing.test.mjs
  scripts/__tests__/retrospective-routing.test.mjs
  scripts/__tests__/preview-publication.test.mjs
  scripts/__tests__/workflow-contraction.test.mjs
  scripts/__tests__/matt-workflow-e2e.test.mjs
  scripts/__tests__/verify-branch-topology.test.mjs
)

for suite in "${test_suites[@]}"; do
  node --test "$suite" || fail "$suite failed"
done

for file in AGENTS.md docs/workflow.md .agents/skills/taisa-workflow/SKILL.md; do
  rg -qi 'Linear.*sole live authority|sole live authority.*Linear' "$file" ||
    fail "$file does not preserve Linear authority"
  rg -qi 'Linear.*unavailable|offline fallback' "$file" ||
    fail "$file does not fail closed when Linear is unavailable"
done

rg -q 'Matt-first engineering router' AGENTS.md || fail "Matt router is missing"
rg -q 'hard bug.*diagnosing-bugs' AGENTS.md || fail "bug route is missing"
rg -q 'foggy.*wayfinder' AGENTS.md || fail "foggy-work route is missing"
rg -q 'one focused session.*implement' AGENTS.md || fail "one-session route is missing"
rg -q 'multi-session.*to-spec.*to-tickets' AGENTS.md || fail "multi-session route is missing"
rg -q 'closeout.*retro' AGENTS.md || fail "retrospective route is missing"

rg -q 'docs/agents/issue-tracker.md' .agents/skills/taisa-workflow/SKILL.md ||
  fail "Linear adapter pointer is missing"
rg -q 'docs/design-system.md' .agents/skills/taisa-workflow/SKILL.md ||
  fail "Product adapter pointer is missing"
rg -q 'docs/workflow.md' .agents/skills/taisa-workflow/SKILL.md ||
  fail "delivery adapter pointer is missing"

rg -q 'REPAIR_QUARANTINE' docs/workflow.md || fail "repair contract is missing"
rg -q 'candidate-freeze contract' docs/workflow.md || fail "candidate freeze is missing"
rg -q 'Browser simulator review' docs/workflow.md || fail "browser review is missing"
rg -q 'Canonical preview and feedback authority' docs/workflow.md ||
  fail "canonical Preview contract is missing"
rg -q 'verify-branch-topology.sh build' docs/workflow.md || fail "build topology gate is missing"
rg -q 'verify-branch-topology.sh ship' docs/workflow.md || fail "Ship topology gate is missing"
rg -q 'preview-sync' docs/workflow.md || fail "Preview synchronization gate is missing"

test ! -e docs/roadmap.md || fail "repository roadmap duplicates Linear"
test ! -e docs/backlog.md || fail "repository backlog duplicates Linear"

echo "Workflow verification passed."
