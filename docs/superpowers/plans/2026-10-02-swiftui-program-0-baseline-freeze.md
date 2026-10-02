# SwiftUI Program 0 Baseline Freeze Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile Taisa's active React Native work into one explicitly approved, reproducible parity baseline and publish the machine-verifiable catalog and reference evidence that every later SwiftUI slice must match.

**Architecture:** Program 0 adds a small Node-based verification tool under `scripts/swiftui-baseline/` and versioned evidence under `docs/migration/swiftui/`. The tool captures content-free Git/worktree facts, validates catalog coverage and reference hashes, and fails closed when a source, route, fixture, or required field is unaccounted for. Human product judgment remains explicit: the tooling proposes and verifies a candidate, while Baah approves the actual freeze before the tag and final status change.

**Tech Stack:** Git, Bash, Node.js built-in test runner, ECMAScript modules, Markdown, JSON, SHA-256, existing Expo/React Native preview runtime

**Spec:** `docs/superpowers/specs/2026-10-02-swiftui-native-rebuild-design.md`

## Global Constraints

- This plan covers Program 0 only: baseline reconciliation, parity catalog, reference evidence, and freeze.
- Do not create `apple/`, write Swift, select native dependencies, or begin a Product slice.
- The candidate baseline must preserve the approved local-first authority boundary and post-Send streaming transcription decision.
- `preview/taisa` remains the only authoritative React Native device-QA runtime.
- Preserve every dirty worktree, untracked user file, unique commit, and source branch; this plan deletes nothing.
- Do not log or capture readable production data. Reference fixtures and media use synthetic content only.
- `719180012de745e3b507ed93eadbe7d8a951331c` is an observed candidate, not the frozen baseline.
- No tag or freeze declaration is created until Baah approves the candidate evidence.
- The frozen tag name is `baseline/swiftui-parity-v1`.
- Product-slice plans remain blocked until Program 0 reaches Review and the baseline freeze is approved.

## File Structure

- Create `scripts/swiftui-baseline/lib.mjs` — pure parsing, normalization, hashing, and validation functions.
- Create `scripts/swiftui-baseline/capture.mjs` — read-only repository/worktree capture that writes the candidate manifest.
- Create `scripts/swiftui-baseline/verify.mjs` — fail-closed verifier for manifest, catalog, fixtures, media hashes, and freeze state.
- Create `scripts/swiftui-baseline/__tests__/lib.test.mjs` — pure unit tests for rejection and normalization behavior.
- Create `scripts/swiftui-baseline/__tests__/verify.test.mjs` — temporary-fixture integration tests for complete and incomplete evidence sets.
- Modify `package.json` — expose `capture:swiftui-baseline` and `verify:swiftui-baseline`.
- Create `docs/migration/swiftui/baseline-manifest.json` — captured source/worktree/revision evidence and approved candidate identity.
- Create `docs/migration/swiftui/parity-catalog.md` — screen, state, flow, copy, accessibility, API, fixture, and comparison contract.
- Create `docs/migration/swiftui/program-ledger.md` — program/slice status, dependencies, approvals, critical-fix parity ledger, and accepted differences.
- Create `docs/migration/swiftui/reference-media/manifest.json` — SHA-256-indexed synthetic reference captures.
- Create `docs/migration/swiftui/reference-media/README.md` — capture naming, device/runtime procedure, and privacy constraints.
- Create `docs/migration/swiftui/performance-baseline.md` — measured React Native reference values and measurement protocol.
- Modify `scripts/verify-workflow.sh` — require Program 0 artifacts and verifier once the baseline is frozen.
- Modify `docs/workflow.md`, `docs/roadmap.md`, and `docs/features/swiftui-native-rebuild.md` — reflect Program 0 Build/Review transitions and freeze evidence.

## Review Focus

- A dirty or detached worktree must be represented exactly and must never be normalized into a clean branch.
- A source branch with unique commits or no upstream must remain unresolved until its disposition and accounting evidence are explicit.
- A new Expo route or required flow absent from the catalog must fail verification.
- A changed or missing reference-media file must fail its SHA-256 check.
- A manifest whose approved commit, tag target, remote preview revision, and signed reference revision disagree must fail closed.

---

### Task 1: Build the fail-closed baseline evidence library

**Files:**
- Create: `scripts/swiftui-baseline/lib.mjs`
- Create: `scripts/swiftui-baseline/__tests__/lib.test.mjs`

**Interfaces:**
- Produces: `normalizeWorktree(record): WorktreeRecord`
- Produces: `validateManifest(manifest): string[]`
- Produces: `parseCatalogRows(markdown): CatalogRow[]`
- Produces: `validateCatalogCoverage({ routes, rows }): string[]`
- Produces: `sha256File(path): Promise<string>`

- [ ] **Step 1: Write failing normalization and validation tests**

```javascript
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeWorktree,
  validateCatalogCoverage,
  validateManifest,
} from '../lib.mjs';

test('preserves dirty and detached worktree evidence', () => {
  assert.deepEqual(normalizeWorktree({
    path: '/repo/wt',
    head: 'abc123',
    branch: null,
    dirty: [' M mobile/app/_layout.tsx', '?? notes.txt'],
    upstream: null,
    uniqueCommits: ['abc123'],
  }), {
    path: '/repo/wt',
    head: 'abc123',
    branch: null,
    detached: true,
    dirty: [' M mobile/app/_layout.tsx', '?? notes.txt'],
    upstream: null,
    uniqueCommits: ['abc123'],
  });
});

test('rejects a baseline with unresolved unique work', () => {
  const errors = validateManifest({
    schemaVersion: 1,
    candidate: { commit: 'abc123', remotePreviewCommit: 'abc123' },
    sources: [{
      name: 'feature/example',
      head: 'def456',
      dirty: [],
      uniqueCommits: ['def456'],
      disposition: 'unresolved',
      accountedBy: [],
    }],
  });
  assert.match(errors.join('\n'), /unresolved unique work/);
});

test('requires one catalog row for every route', () => {
  const errors = validateCatalogCoverage({
    routes: ['app/(tabs)/index.tsx', 'app/chat/index.tsx'],
    rows: [{ source: 'app/(tabs)/index.tsx', catalogId: 'home.default' }],
  });
  assert.deepEqual(errors, ['Missing catalog coverage: app/chat/index.tsx']);
});
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `node --test scripts/swiftui-baseline/__tests__/lib.test.mjs`

Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `scripts/swiftui-baseline/lib.mjs`.

- [ ] **Step 3: Implement the pure evidence functions**

```javascript
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';

export function normalizeWorktree(record) {
  return {
    ...record,
    detached: record.branch === null,
    dirty: [...record.dirty].sort(),
    uniqueCommits: [...record.uniqueCommits].sort(),
  };
}

export function validateManifest(manifest) {
  const errors = [];
  if (manifest.schemaVersion !== 1) errors.push('Unsupported manifest schema');
  if (!manifest.candidate?.commit) errors.push('Missing candidate commit');
  for (const source of manifest.sources ?? []) {
    if ((source.uniqueCommits?.length || source.dirty?.length)
      && source.disposition === 'unresolved') {
      errors.push(`Source ${source.name} has unresolved unique work`);
    }
    if (source.disposition === 'accounted' && !source.accountedBy?.length) {
      errors.push(`Source ${source.name} is accounted without evidence`);
    }
  }
  return errors;
}

export function validateCatalogCoverage({ routes, rows }) {
  const covered = new Set(rows.map((row) => row.source));
  const ids = rows.map((row) => row.catalogId);
  const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index);
  return [
    ...new Set(duplicates.map((id) => `Duplicate catalog ID: ${id}`)),
    ...routes
    .filter((route) => !covered.has(route))
    .map((route) => `Missing catalog coverage: ${route}`),
  ];
}

export function parseCatalogRows(markdown) {
  return markdown
    .split('\n')
    .filter((line) => /^\| PC-[0-9]{3} \|/.test(line))
    .map((line) => {
      const cells = line.split('|').slice(1, -1).map((cell) => cell.trim());
      const [catalogId, journey, source, state, fixture, expectedBehavior,
        accessibility, apiDecision, reference, nativeOwner, status] = cells;
      return {
        catalogId,
        journey,
        source,
        state,
        fixture,
        expectedBehavior,
        accessibility,
        apiDecision,
        reference,
        nativeOwner,
        status,
      };
    });
}

export async function sha256File(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
```

- [ ] **Step 4: Run the unit tests**

Run: `node --test scripts/swiftui-baseline/__tests__/lib.test.mjs`

Expected: PASS, 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/swiftui-baseline/lib.mjs scripts/swiftui-baseline/__tests__/lib.test.mjs
git commit -m "test: define SwiftUI baseline evidence rules"
```

### Task 2: Capture every active source without modifying it

**Files:**
- Create: `scripts/swiftui-baseline/capture.mjs`
- Create: `scripts/swiftui-baseline/__tests__/verify.test.mjs`
- Create: `docs/migration/swiftui/baseline-manifest.json`
- Modify: `package.json`

**Interfaces:**
- Consumes: Git `worktree list --porcelain -z`, `status --porcelain=v1`, `for-each-ref`, `merge-base`, and `rev-list`
- Produces: schema-versioned manifest with `capturedAt`, `mainCommit`, `remotePreviewCommit`, `candidate`, `sources`, and `requiredRoutes`

- [ ] **Step 1: Write an integration test that rejects incomplete evidence**

Create a temporary evidence directory and invoke the verifier with an explicit root so production repository state is never touched.

```javascript
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

async function runFixtureVerifier(manifest) {
  const root = await mkdtemp(join(tmpdir(), 'taisa-baseline-test-'));
  await writeFile(
    join(root, 'baseline-manifest.json'),
    JSON.stringify({ schemaVersion: 1, candidate: { commit: 'abc123' }, ...manifest }),
  );
  return spawnSync(
    process.execPath,
    ['scripts/swiftui-baseline/verify.mjs', '--evidence-root', root],
    { cwd: process.cwd(), encoding: 'utf8' },
  );
}

test('verification fails while a unique source is unresolved', async () => {
  const result = await runFixtureVerifier({
    sources: [{
      name: 'feature/unique',
      uniqueCommits: ['def456'],
      dirty: [],
      disposition: 'unresolved',
      accountedBy: [],
    }],
  });
  assert.equal(result.code, 1);
  assert.match(result.stderr, /unresolved unique work/);
});
```

- [ ] **Step 2: Run the integration test and verify it fails**

Run: `node --test scripts/swiftui-baseline/__tests__/verify.test.mjs`

Expected: FAIL because `capture.mjs` and `verify.mjs` do not exist.

- [ ] **Step 3: Implement read-only capture**

`capture.mjs` must:

1. fetch nothing and mutate nothing;
2. resolve the repository common directory;
3. enumerate all linked worktrees dynamically rather than using the old fixed branch list;
4. capture branch/detached state, HEAD, upstream, dirty paths, unique commits versus `origin/main`, and patch SHA-256 for tracked dirty state;
5. enumerate `mobile/app/**/*.tsx` routes from the candidate commit while excluding `_layout.tsx`;
6. preserve existing human disposition/accounting fields when recapturing the same source;
7. write stable, sorted JSON to `docs/migration/swiftui/baseline-manifest.json`.

Use `execFileSync('git', args, { encoding: 'utf8' })`; do not invoke a shell or interpolate Git output into commands.

- [ ] **Step 4: Add root scripts**

```json
{
  "scripts": {
    "capture:swiftui-baseline": "node scripts/swiftui-baseline/capture.mjs",
    "verify:swiftui-baseline": "node scripts/swiftui-baseline/verify.mjs"
  }
}
```

Merge these entries into the existing `scripts` object without changing unrelated commands.

- [ ] **Step 5: Capture the current candidate evidence**

Run: `npm run capture:swiftui-baseline -- --candidate=origin/preview/taisa`

Expected: the manifest records `remotePreviewCommit` as `719180012de745e3b507ed93eadbe7d8a951331c`, dynamically lists every current worktree, and marks sources with unique or dirty work as `unresolved`.

- [ ] **Step 6: Run the integration tests**

Run: `node --test scripts/swiftui-baseline/__tests__/*.test.mjs`

Expected: PASS; the fixture with unresolved work fails verification internally while the complete fixture passes.

- [ ] **Step 7: Commit**

```bash
git add package.json scripts/swiftui-baseline docs/migration/swiftui/baseline-manifest.json
git commit -m "chore: capture SwiftUI baseline evidence"
```

### Task 3: Reconcile candidate sources into explicit dispositions

**Files:**
- Modify: `docs/migration/swiftui/baseline-manifest.json`
- Modify: `docs/reconciliation/current-experience-inventory.md`
- Create: `docs/migration/swiftui/program-ledger.md`

**Interfaces:**
- Consumes: Task 2 source records and existing reconciliation evidence
- Produces: one of `accounted`, `excluded`, `critical-fix`, or `unresolved` for every source with commit evidence

- [ ] **Step 1: Run the current-experience audit**

Run: `bash scripts/audit-current-experience.sh`

Expected: output for every script-known legacy branch; missing/deleted branches are evidence to update the script, not permission to omit them.

- [ ] **Step 2: Compare dynamic capture with the legacy inventory**

For every worktree/branch in `baseline-manifest.json`, record:

```json
{
  "disposition": "accounted",
  "reason": "Behavior exists in candidate through the listed commits",
  "accountedBy": ["719180012de745e3b507ed93eadbe7d8a951331c"],
  "owner": "Program 0"
}
```

Use `excluded` only when the approved scope/spec excludes the work, and cite that section in `reason`. Use `critical-fix` only for behavior that must land before freeze. Leave uncertainty as `unresolved`; do not guess.

- [ ] **Step 3: Write the program ledger**

The ledger must contain:

- program stages 0–5 with status, prerequisite, branch/plan, gate, and evidence;
- a source-accounting table mirroring the manifest;
- a critical-fix parity table with React Native commit, native owner, regression evidence, and status;
- an accepted-differences table with catalog ID, severity, decision owner, reason, and approval evidence;
- a decision log stating that no later plan is authorized by Program 0 approval.

- [ ] **Step 4: Stop for Baah's source-disposition decision**

Present every remaining `unresolved` or `critical-fix` row with its unique commits and affected behavior. Do not select or freeze a baseline until Baah resolves them.

- [ ] **Step 5: Re-capture and verify source accounting**

Run: `npm run capture:swiftui-baseline -- --candidate="$(node -e "const m=require('./docs/migration/swiftui/baseline-manifest.json'); process.stdout.write(m.candidate.ref)")"`

Run: `npm run verify:swiftui-baseline`

Expected: source-accounting checks pass; catalog/media checks may still report their not-yet-created artifacts.

- [ ] **Step 6: Commit**

```bash
git add docs/migration/swiftui/baseline-manifest.json docs/migration/swiftui/program-ledger.md docs/reconciliation/current-experience-inventory.md
git commit -m "docs: reconcile SwiftUI parity sources"
```

### Task 4: Build the complete parity catalog

**Files:**
- Create: `docs/migration/swiftui/parity-catalog.md`
- Modify: `scripts/swiftui-baseline/verify.mjs`
- Modify: `scripts/swiftui-baseline/__tests__/verify.test.mjs`

**Interfaces:**
- Consumes: `requiredRoutes` from the approved candidate manifest
- Produces: unique `PC-NNN` entries with source, state, fixture, expected behavior, accessibility, reference media, API contract, and owner

- [ ] **Step 1: Add failing catalog-verification tests**

Cover duplicate IDs, an unmapped route, a missing fixture, a missing accessibility expectation, and a reference-media path absent from the media manifest.

- [ ] **Step 2: Run tests and verify failure**

Run: `node --test scripts/swiftui-baseline/__tests__/verify.test.mjs`

Expected: FAIL because catalog validation is incomplete.

- [ ] **Step 3: Implement catalog validation**

`verify.mjs` must require these columns for every `PC-NNN` row:

```text
ID | Journey | Source | State | Fixture | Expected behavior | Accessibility | API/decision | Reference | Native owner | Status
```

Reject duplicate IDs, empty cells, unknown status values, required routes without rows, reference paths missing from the media manifest, and catalog rows whose source does not exist at the approved baseline commit.

- [ ] **Step 4: Author the parity catalog from executable and QA evidence**

At minimum, catalog:

- app launch, onboarding, privacy lock, and recovery states;
- Home default/loading/empty/error/attention states;
- Chats loading/empty/error/grouped/resume states;
- conversation text, voice-ready, recording, paused, transcribing, uncertain, no-speech, coaching, retry, proposal, conflict, and feedback states;
- Me/profile, notifications, lock, export, restore, destructive confirmation, and failure states;
- tab transitions, chat-card open/close, reduced motion, Dynamic Type, VoiceOver, increased contrast, and reduced transparency;
- offline, permission-denied, interrupted audio, background/foreground, and backend failure paths.

Use synthetic fixtures named `fixture.onboarding.new`, `fixture.home.attention`, `fixture.chats.history`, `fixture.coaching.text`, `fixture.coaching.voice-clear`, `fixture.coaching.voice-uncertain`, `fixture.coaching.voice-no-speech`, and `fixture.me.recovery`.

- [ ] **Step 5: Verify catalog coverage**

Run: `npm run verify:swiftui-baseline`

Expected: route/catalog/fixture checks pass; uncaptured media references remain the only permitted failure at this point.

- [ ] **Step 6: Commit**

```bash
git add docs/migration/swiftui/parity-catalog.md scripts/swiftui-baseline
git commit -m "docs: catalog React Native parity behavior"
```

### Task 5: Capture hashed reference media and performance evidence

**Files:**
- Create: `docs/migration/swiftui/reference-media/README.md`
- Create: `docs/migration/swiftui/reference-media/manifest.json`
- Create: reference files enumerated exactly in `docs/migration/swiftui/reference-media/manifest.json`, named `PC-NNN__device__state.png` or `PC-NNN__device__motion.mov`
- Create: `docs/migration/swiftui/performance-baseline.md`
- Modify: `docs/migration/swiftui/parity-catalog.md`

**Interfaces:**
- Consumes: approved candidate commit, catalog IDs, synthetic fixtures, and canonical `preview/taisa` runtime
- Produces: media records `{ catalogId, path, sha256, device, os, viewport, commit, fixture, capturedAt }`

- [ ] **Step 1: Confirm canonical runtime before capture**

Run:

```bash
git -C /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/preview-taisa status --short --branch
git -C /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/preview-taisa rev-parse HEAD
git rev-parse origin/preview/taisa
```

Expected: clean `preview/taisa`; local HEAD, remote preview, and the approved candidate commit are identical. Stop if any differ.

- [ ] **Step 2: Document the synthetic capture protocol**

The README requires:

- no personal or production content;
- one catalog ID per filename;
- screenshots for static/composite states and short videos for gestures/motion/audio lifecycle;
- device model, OS, viewport, fixture, commit, and capture timestamp;
- unchanged system appearance settings recorded per batch;
- re-capture and re-hash after any approved critical baseline fix.
- repository evidence limited to 10 MB per file and 100 MB total; if a required capture exceeds either limit, record its hash and durable approved storage location in the manifest instead of committing the binary, and make verification fail when that location cannot be resolved.

- [ ] **Step 3: Capture every required reference**

Use filename format `PC-001__iphone__default.png` or `PC-041__iphone__card-close.mov`. Capture iPhone references for every visual catalog row and iPad references for all shell, navigation, modal/popover, keyboard, rotation, and multitasking rows.

- [ ] **Step 4: Record measured performance**

Measure at least five release-mode runs on the agreed reference iPhone and iPad for:

- cold and warm launch;
- peak memory for Home, long Chats history, and active conversation;
- database open and representative Home/Chats queries;
- list scrolling and coordinated navigation frame stability;
- tap-to-record readiness;
- stop-to-first-transcript delta;
- clear-result-to-coaching-start delta;
- installed app size and exported archive size.

Record device, OS, build/commit, tools, run count, raw observations, median, worst case, and environmental caveats. These are reference measurements; Program 1 will propose pass thresholds for Baah approval.

- [ ] **Step 5: Generate and verify media hashes**

Run: `npm run capture:swiftui-baseline -- --candidate="$(node -e "const m=require('./docs/migration/swiftui/baseline-manifest.json'); process.stdout.write(m.candidate.ref)")" --refresh-media-hashes`

Run: `npm run verify:swiftui-baseline`

Expected: every catalog reference exists, hashes match, metadata matches the approved commit/fixture, and no required catalog row lacks evidence.

- [ ] **Step 6: Commit**

```bash
git add docs/migration/swiftui/reference-media docs/migration/swiftui/parity-catalog.md docs/migration/swiftui/performance-baseline.md
git commit -m "docs: capture React Native parity references"
```

### Task 6: Freeze the approved baseline and enforce it

**Files:**
- Modify: `scripts/verify-workflow.sh`
- Modify: `scripts/swiftui-baseline/verify.mjs`
- Modify: `scripts/swiftui-baseline/__tests__/verify.test.mjs`
- Modify: `docs/migration/swiftui/baseline-manifest.json`
- Modify: `docs/migration/swiftui/program-ledger.md`
- Modify: `docs/features/swiftui-native-rebuild.md`
- Modify: `docs/workflow.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: Baah-approved candidate, complete catalog, verified media, and performance evidence
- Produces: immutable annotated tag `baseline/swiftui-parity-v1` and green repository verification

- [ ] **Step 1: Add failing freeze-integrity tests**

Test mismatches between approved commit, `origin/preview/taisa`, tag target, media commit, and catalog revision. Each mismatch must produce a distinct nonzero failure.

- [ ] **Step 2: Run tests and verify failure**

Run: `node --test scripts/swiftui-baseline/__tests__/*.test.mjs`

Expected: FAIL until tag/freeze integrity is implemented.

- [ ] **Step 3: Implement freeze verification**

`verify.mjs` must, when `manifest.status === "frozen"`:

- require `approvedBy: "Baah"` and nonempty `approvedAt`;
- resolve `baseline/swiftui-parity-v1` and require it equals `candidate.commit`;
- require `origin/preview/taisa`, signed reference commit, media commit, and candidate commit to agree;
- reject unresolved/critical-fix sources;
- require every catalog row to be `captured` or explicitly `accepted-difference`;
- verify every media SHA-256 and required fixture.

- [ ] **Step 4: Request Baah's explicit baseline-freeze approval**

Present the candidate commit, source-accounting summary, catalog coverage count, known defects, accepted differences, verification output, device/media matrix, and performance evidence. Do not tag or mark frozen before approval.

- [ ] **Step 5: Create and push the immutable baseline tag after approval**

```bash
git tag -a baseline/swiftui-parity-v1 "$(node -e "const m=require('./docs/migration/swiftui/baseline-manifest.json'); process.stdout.write(m.candidate.commit)")" -m "Freeze React Native baseline for SwiftUI parity"
git push origin baseline/swiftui-parity-v1
```

Confirm the tag target on GitHub/remote before changing manifest status.

- [ ] **Step 6: Finalize status and workflow enforcement**

Set manifest `status` to `frozen`, record Baah and approval date/evidence, set Program 0 to Review in the ledger, and update Active Work to block Program 1 on Program 0 Ship.

Add to `scripts/verify-workflow.sh`:

```bash
test -f docs/migration/swiftui/baseline-manifest.json || fail "SwiftUI baseline manifest is missing"
test -f docs/migration/swiftui/parity-catalog.md || fail "SwiftUI parity catalog is missing"
npm run verify:swiftui-baseline || fail "SwiftUI baseline verification failed"
```

- [ ] **Step 7: Run the complete Program 0 verification**

Run:

```bash
node --test scripts/swiftui-baseline/__tests__/*.test.mjs
npm run verify:swiftui-baseline
npm run verify:workflow
git diff --check
git status --short --branch
```

Expected: all tests pass; baseline verifier and workflow verifier pass; diff check is clean; only intended Program 0 files are changed before the final commit.

- [ ] **Step 8: Commit**

```bash
git add package.json scripts/swiftui-baseline scripts/verify-workflow.sh docs/migration/swiftui docs/features/swiftui-native-rebuild.md docs/workflow.md docs/roadmap.md
git commit -m "docs: freeze React Native SwiftUI parity baseline"
```

## Closeout

Complete during Program 0 Review with the frozen commit/tag, source-accounting totals, catalog/media coverage, measured reference matrix, verification commands/results, accepted differences, unresolved non-blocking debt, canonical documents updated, pull request, and merge evidence.
