#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Workflow verification failed: $1" >&2
  exit 1
}

test -f AGENTS.md || fail "AGENTS.md is missing"
test -f docs/workflow.md || fail "docs/workflow.md is missing"
test -f .agents/skills/taisa-workflow/SKILL.md || fail "Taisa workflow orchestrator is missing"
test -f .agents/skills/taisa-workflow/templates/bounded-goal.md ||
  fail ".agents/skills/taisa-workflow/templates/bounded-goal.md is missing"
test -f docs/project-memory.md || fail "project memory index is missing"
test -f docs/decisions/README.md || fail "decision record guide is missing"
test -f docs/decisions/0001-use-repository-native-project-memory.md || fail "initial project memory decision is missing"
test -f docs/learnings.md || fail "reusable learning log is missing"
node scripts/canonical-origin.mjs "$(git remote get-url origin)" || fail "origin does not use the canonical Taisa URL"

active_skills=(
  taisa-workflow
  scope-writer
  design-handoff
  build-component
  motion
  emil-design-eng
)

for skill in "${active_skills[@]}"; do
  canonical_skill=".agents/skills/$skill/SKILL.md"
  compatibility_skill=".claude/skills/$skill/SKILL.md"

  test -f "$canonical_skill" || fail "$skill is missing from the canonical agent-neutral skill tree"
  test -L "$compatibility_skill" ||
    fail "$compatibility_skill is missing or independently editable"
  test -f "$compatibility_skill" || fail "$compatibility_skill resolves to a missing file"
  test "$(cd "$(dirname "$compatibility_skill")" && realpath "$(basename "$compatibility_skill")")" = \
    "$(realpath "$canonical_skill")" || fail "$compatibility_skill does not forward to the canonical skill"
done

# Linear is the sole live delivery authority. These checks intentionally stay
# offline: they verify repository contracts without reading or mutating Linear.
test ! -e docs/roadmap.md || fail "repository roadmap duplicates Linear live authority"
test ! -e docs/backlog.md || fail "repository backlog duplicates Linear task intake"

for authority_file in AGENTS.md CLAUDE.md docs/workflow.md .agents/skills/taisa-workflow/SKILL.md; do
  rg -qi 'Linear.*sole live authority|sole live authority.*Linear' "$authority_file" ||
    fail "$authority_file does not declare Linear as the sole live authority"
  rg -qi 'Linear.*unavailable|offline fallback' "$authority_file" ||
    fail "$authority_file is missing the Linear-unavailable fallback"
done

if rg -n 'Active Work table|docs/roadmap\.md|docs/backlog\.md' \
  AGENTS.md CLAUDE.md docs/workflow.md .agents/skills/taisa-workflow/SKILL.md docs/project-memory.md; then
  fail "active repository instructions still reference duplicate live authority"
fi

if rg -n 'No formal Work Map, scope doc, or Linear issue|No Linear issue|Linear issues are created only' \
  AGENTS.md CLAUDE.md docs/workflow.md .agents/skills/taisa-workflow/SKILL.md docs/project-memory.md; then
  fail "active repository instructions still permit actionable work without Linear intake"
fi

require_workflow_pattern() {
  local file="$1" pattern="$2" description="$3"
  rg -qi "$pattern" "$file" || fail "$file is missing $description"
}

for invariant in \
  'bounded Goal run' \
  'kickoff bundle' \
  'high-risk predicates' \
  'REPAIR_QUARANTINE' \
  'Unfixed; blocking; unshippable'; do
  require_workflow_pattern docs/workflow.md "$invariant" "bounded-delivery invariant: $invariant"
done
require_workflow_pattern docs/workflow.md 'Platform.*Product.*Integration.*exclusive|exclusive.*Platform.*Product.*Integration' \
  'exclusive Platform/Product/Integration ownership'

for invariant in \
  'active Goal.*solely.*wait|no active Goal.*wait' \
  'QA_READY' \
  'MATERIAL_REAPPROVAL_REQUIRED' \
  'repair-release gate' \
  'no successor issue|never select.*successor'; do
  require_workflow_pattern .agents/skills/taisa-workflow/SKILL.md "$invariant" \
    "bounded Goal routing: $invariant"
done

goal_template=.agents/skills/taisa-workflow/templates/bounded-goal.md
for invariant in \
  'Primary Linear issue' \
  'Milestone context' \
  'Run type' \
  'Entry state and evidence' \
  'Terminal outcome' \
  'Approved kickoff or Scope/Plan evidence' \
  'Work slices' \
  'Branch/worktree' \
  'Canonical preview baseline' \
  'Acceptance criteria' \
  'Verification matrix' \
  'Permitted mutations' \
  'Prohibited actions' \
  'Repair evidence' \
  'unchanged polling' \
  'Never infer approval' \
  'successor issue' \
  'do not remain active solely.*wait' \
  'Next Baah gate'; do
  require_workflow_pattern "$goal_template" "$invariant" "Goal-template field: $invariant"
done

for forbidden_pattern in \
  '^[[:space:]-]*(continue|loop|work).*(complete|ship).*(product|everything)' \
  '^[[:space:]-]*(select|start|advance).*(next|successor).*(issue|work)' \
  '^[[:space:]-]*(poll|retry|check again).*until' \
  '^[[:space:]-]*(wait|remain active).*(Baah|external state)'; do
  if rg -ni "$forbidden_pattern" "$goal_template"; then
    fail "$goal_template contains semantically unbounded instruction: $forbidden_pattern"
  fi
done

require_workflow_pattern docs/workflow.md 'inapplicable.*evidence|evidence.*inapplicable' \
  'evidence-backed repair-gate inapplicability'
require_workflow_pattern .agents/skills/taisa-workflow/SKILL.md \
  'inapplicable.*evidence|evidence.*inapplicable' \
  'evidence-backed repair-gate inapplicability'
require_workflow_pattern "$goal_template" 'each repair-release.*pass.*inapplicable.*evidence' \
  'per-item repair-release disposition'

for forbidden in \
  'continue until the complete product ships' \
  'select the next highest-priority issue and continue' \
  'poll again until complete' \
  'silence counts as approval'; do
  if rg -n -F "$forbidden" "$goal_template"; then
    fail "$goal_template contains forbidden unbounded instruction: $forbidden"
  fi
done

for recommendation_file in \
  docs/workflow.md \
  .agents/skills/taisa-workflow/SKILL.md \
  .agents/skills/taisa-workflow/templates/bounded-goal.md; do
  require_workflow_pattern "$recommendation_file" 'exactly one.*Recommended next outcome|Recommended next outcome.*exactly one' \
    'exactly-one Recommended next outcome contract'
  require_workflow_pattern "$recommendation_file" 'exactly one.*No next outcome recommended|No next outcome recommended.*exactly one' \
    'exactly-one no-safe-candidate recommendation form'
  require_workflow_pattern "$recommendation_file" 'priorit(y|ies).*blocker.*dependenc.*approval|approval.*dependenc.*blocker.*priorit' \
    'Linear recommendation evidence inputs'
  require_workflow_pattern "$recommendation_file" 'Recommended next outcome.*Reason:.*Next Baah gate:' \
    'recommended-outcome reason and gate form'
  require_workflow_pattern "$recommendation_file" 'No next outcome recommended.*Reason:.*Next Baah gate:' \
    'no-outcome reason and gate form'
  require_workflow_pattern "$recommendation_file" 'never provide an alternatives list' \
    'no-alternatives recommendation boundary'
  require_workflow_pattern "$recommendation_file" 'explicit.*kickoff|kickoff.*explicit' \
    'explicit successor kickoff boundary'
done

for recommendation_file in \
  docs/workflow.md \
  .agents/skills/taisa-workflow/SKILL.md \
  .agents/skills/taisa-workflow/templates/bounded-goal.md; do
  for mutation_boundary in \
    'never reopen or start the successor issue' \
    'never create the successor branch or Goal' \
    'never change the successor status' \
    'never begin the successor work'; do
    require_workflow_pattern "$recommendation_file" "$mutation_boundary" \
      "successor mutation prohibition: $mutation_boundary"
  done
done

rg -q '31b0d99c-6f74-4c9c-af2a-12e6e25aabe0' \
  .agents/skills/taisa-workflow/SKILL.md || fail "Taisa Linear project ID is missing"
rg -q 'e95356d8-17f7-4700-bdfe-222782bea546' \
  .agents/skills/taisa-workflow/SKILL.md || fail "Taisa Linear team ID is missing"
rg -qi 'every actionable task.*Linear issue|Linear issue.*every actionable task' \
  .agents/skills/taisa-workflow/SKILL.md || fail "universal Linear issue intake is missing"

for authority_file in docs/workflow.md .agents/skills/taisa-workflow/SKILL.md; do
  rg -qi 'Captured.*Watching.*Candidate.*Planned.*Shipped.*Dropped' "$authority_file" ||
    fail "$authority_file is missing the deferred-capability lifecycle"
  rg -qi 'first Monday.*09:00.*Africa/Accra' "$authority_file" ||
    fail "$authority_file is missing the monthly reconciliation cadence"
  rg -qi 'quiet.*no.*meaningful change|no meaningful change.*quiet' "$authority_file" ||
    fail "$authority_file is missing the monthly reconciliation quiet-state boundary"
  rg -qi 'never approves.*Scope.*Plan.*priority.*lifecycle promotion.*Ship' "$authority_file" ||
    fail "$authority_file is missing the complete monthly reconciliation approval boundary"
done

if rg -n 'current named voice deferrals|Named voice deferrals' \
  docs/workflow.md .agents/skills/taisa-workflow/SKILL.md; then
  fail "repository instructions duplicate Linear's current deferred-capability inventory"
fi

if rg -n 'docs/features/<|Roadmap status vocabulary|output to correct location.*docs/features' \
  .agents/skills/scope-writer/SKILL.md .agents/skills/design-handoff/SKILL.md; then
  fail "active skills still treat repository Scope or roadmap state as live authority"
fi

rg -q 'npx expo run:ios.*npx expo eject|npx expo eject.*npx expo run:ios' AGENTS.md ||
  fail "AGENTS.md is missing the approval boundary for legacy native project generation"

rg -q 'main.*only permanent branch|only permanent branch.*main' docs/workflow.md || fail "canonical main policy is missing"
rg -q '<type>/<short-kebab-case-description>' docs/workflow.md || fail "typed branch naming policy is missing"
rg -qi 'squash merge' docs/workflow.md || fail "squash merge policy is missing"
rg -q 'Ship approval|Ship gate' docs/workflow.md || fail "Ship authorization policy is missing"
test -f scripts/verify-branch-topology.sh || fail "branch topology verifier is missing"
test -f scripts/__tests__/verify-branch-topology.test.mjs || fail "branch topology verifier tests are missing"
node --test scripts/__tests__/verify-branch-topology.test.mjs
for topology_mode in build ship preview-sync; do
  rg -q "verify-branch-topology.sh ${topology_mode}" docs/workflow.md ||
    fail "workflow is missing the ${topology_mode} topology gate"
  rg -q "verify-branch-topology.sh ${topology_mode}" .agents/skills/taisa-workflow/SKILL.md ||
    fail "orchestrator is missing the ${topology_mode} topology gate"
done
rg -q 'merge-tree' scripts/verify-branch-topology.sh || fail "Ship topology gate lacks a conflict dry run"
for efficiency_invariant in \
  'smallest applicable verification' \
  'reuse fresh evidence' \
  'independent checks concurrently' \
  'three materially distinct unsuccessful approaches'; do
  rg -qi "$efficiency_invariant" docs/workflow.md ||
    fail "workflow is missing efficiency invariant: $efficiency_invariant"
  rg -qi "$efficiency_invariant" .agents/skills/taisa-workflow/SKILL.md ||
    fail "orchestrator is missing efficiency invariant: $efficiency_invariant"
done
rg -q 'superpowers:brainstorming' .agents/skills/taisa-workflow/SKILL.md || fail "brainstorming routing is missing"
rg -q 'superpowers:verification-before-completion' .agents/skills/taisa-workflow/SKILL.md || fail "completion verification routing is missing"
rg -q '\.agents/skills/taisa-workflow/SKILL\.md' AGENTS.md || fail "AGENTS.md does not load the canonical orchestrator"
rg -q 'docs/workflow\.md' AGENTS.md || fail "AGENTS.md does not load the workflow source"
rg -q '^### Work Map' docs/workflow.md || fail "pre-planning Work Map contract is missing"
rg -q '^### Discussion Map' docs/workflow.md || fail "selected-slice Discussion Map contract is missing"
rg -qi 'layman meaning.*technical truth' docs/workflow.md || fail "balanced architecture-diagram contract is missing"
rg -q 'Platform discussion' .agents/skills/taisa-workflow/SKILL.md || fail "Platform discussion agenda is missing"
rg -q 'Product discussion' .agents/skills/taisa-workflow/SKILL.md || fail "Product discussion agenda is missing"
rg -q 'Integration discussion' .agents/skills/taisa-workflow/SKILL.md || fail "integration discussion agenda is missing"
rg -q 'XS.*S.*M.*L.*XL' docs/workflow.md || fail "slice sizing scale is missing"
rg -q 'independent Product foundation' docs/workflow.md || fail "Product skeleton dependency boundary is missing"
rg -q '^### Activation bias' docs/workflow.md || fail "workflow activation bias is missing"
rg -qi 'default.*activat|activate.*default' .agents/skills/taisa-workflow/SKILL.md || fail "orchestrator does not default toward activation"
rg -q '^## Documentation freshness cadence' docs/workflow.md || fail "documentation freshness cadence is missing"
rg -q 'Explicit precedence|explicit precedence' docs/workflow.md || fail "activation precedence is missing"
rg -q 'between Scope and Plan' docs/workflow.md || fail "Product design boundary is missing"
rg -q 'host artifact' docs/workflow.md || fail "embedded diagram ownership is missing"
rg -q 'Canonical documentation authority' docs/workflow.md || fail "canonical documentation authority is missing"
rg -q 'Material change' docs/workflow.md || fail "material-change definition is missing"
rg -q 'Superseded by' docs/workflow.md || fail "superseded-document lifecycle is missing"
test -f scripts/verify-doc-freshness.sh || fail "documentation freshness verifier is missing"

if rg -n '^\| Backlog idea \| Create issue' .agents/skills/taisa-workflow/SKILL.md; then
  fail "backlog-to-Linear contradiction remains"
fi
for startup_file in AGENTS.md CLAUDE.md docs/workflow.md .agents/skills/taisa-workflow/SKILL.md; do
  rg -q 'docs/project-memory\.md' "$startup_file" || fail "$startup_file does not load the project memory index"
done
rg -q '^\*\*Status:\*\* Accepted$' docs/decisions/0001-use-repository-native-project-memory.md || fail "initial project memory decision is not accepted"
rg -q '^\| Date \| Area \| Learning \| Evidence \| Promoted to \|$' docs/learnings.md || fail "learning log table contract is missing"
rg -q 'Closeout' docs/workflow.md || fail "workflow closeout rule is missing"
rg -q 'memory-promotion check' docs/workflow.md || fail "workflow memory promotion rule is missing"
rg -q 'Closeout' .agents/skills/taisa-workflow/SKILL.md || fail "orchestrator closeout rule is missing"
rg -q 'memory-promotion check' .agents/skills/taisa-workflow/SKILL.md || fail "orchestrator memory promotion rule is missing"
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

if rg -n 'One branch per feature: `feature/<name>`' CLAUDE.md docs/workflow.md .agents/skills/taisa-workflow/SKILL.md; then
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
