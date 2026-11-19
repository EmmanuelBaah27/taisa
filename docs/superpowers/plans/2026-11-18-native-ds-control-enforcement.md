# Native DS Control Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make native shared-component adoption fail closed without granting a directory-wide raw-control exemption.

**Architecture:** A checked-in policy names primitive wrapper files individually and fingerprints existing APF-75 migration debt. The native verifier scans Product and composite design-system sources, while workflow authorities make the same boundary mandatory before Build and merge.

**Tech Stack:** Node.js source verifier and tests, Bash workflow verifier, Markdown workflow authorities, SwiftUI source inspection

**Spec:** `docs/superpowers/specs/2026-11-18-native-ds-control-enforcement-design.md`

## Global Constraints

- Existing DS components are mandatory when they cover the interaction.
- Raw platform controls are permitted only in explicitly designated primitive implementation files.
- Missing variants are blocking DS gaps; Product code does not create substitutes.
- APF-75 owns existing full-app migration debt; APF-69 owns the Tasks consumer repair.
- No broad directory allowlist or wildcard exemption.

## Review Focus

- Comments and strings containing `Button(` must not become violations.
- Multiline SwiftUI button declarations must be detected consistently.
- A changed legacy occurrence must fail even when it remains in the same file.
- A removed legacy occurrence must make its policy entry stale and fail verification.
- A primitive registry entry must name a real Swift source beneath the approved DS source root.

---

### Task 1: Native raw-control policy and verifier

**Files:**
- Create: `scripts/native-apple/design-system-control-policy.json`
- Modify: `scripts/native-apple/verify-design-system.mjs`
- Modify: `scripts/native-apple/__tests__/verify-design-system.test.mjs`

**Interfaces:**
- Consumes: Swift source roots and the checked-in JSON policy
- Produces: `rawInteractiveControlViolations({ roots, policyPath })` and fail-closed CLI output

- [ ] Write fixture tests for Product bypass, composite-DS bypass, designated primitive pass, exact legacy pass, changed legacy failure, stale legacy failure, and comments/strings.
- [ ] Run `node --test scripts/native-apple/__tests__/verify-design-system.test.mjs` and confirm the new tests fail.
- [ ] Implement policy loading, Swift lexical sanitization, occurrence fingerprinting, policy validation, and violation reporting.
- [ ] Generate the exact APF-75 legacy baseline and explicitly list genuine primitive wrapper files.
- [ ] Run the focused Node test and confirm it passes.
- [ ] Commit the verifier slice.

### Task 2: Workflow authority and bounded-Goal enforcement

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/workflow.md`
- Modify: `.agents/skills/taisa-workflow/SKILL.md`
- Modify: `.agents/skills/taisa-workflow/templates/bounded-goal.md`
- Modify: `scripts/verify-workflow.sh`

**Interfaces:**
- Consumes: APF-88 invariant and policy classification model
- Produces: consistent workflow rule and mechanical authority-string verification

- [ ] Add failing workflow-verifier assertions for mandatory reuse, designated primitive files, blocking gaps, and no broad module exemption.
- [ ] Run `bash scripts/verify-workflow.sh` and confirm the new assertions fail.
- [ ] Add the smallest consistent authority and Goal-template wording.
- [ ] Run `bash scripts/verify-workflow.sh` and confirm it passes.
- [ ] Run governed-document freshness checks and update `Last updated` metadata only where required.
- [ ] Commit the workflow slice.

### Task 3: Whole-candidate verification

**Files:**
- Verify all files changed by Tasks 1–2

**Interfaces:**
- Consumes: completed verifier and workflow slices
- Produces: exact APF-88 candidate evidence for review

- [ ] Run `node --test scripts/native-apple/__tests__/verify-design-system.test.mjs`.
- [ ] Run `node scripts/native-apple/verify-design-system.mjs`.
- [ ] Run `bash scripts/verify-workflow.sh`.
- [ ] Run applicable `bash scripts/verify-doc-freshness.sh` checks.
- [ ] Run `git diff --check` and inspect the whole diff for a bypass path.
- [ ] Commit any verification-only correction, record the exact commit in APF-88, and stop before APF-69 migration.
