import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeWorktree,
  parseBranchRecords,
  parseWorktreeRecords,
  reconcileDisposition,
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

test('parses newline-delimited NUL branch records without changing branch names', () => {
  const output = [
    'feature/one\0abc123\0origin/feature/one\0',
    'feature/two\0def456\0\0',
    '',
  ].join('\n');

  assert.deepEqual(parseBranchRecords(output), [
    { branch: 'feature/one', head: 'abc123', upstream: 'origin/feature/one' },
    { branch: 'feature/two', head: 'def456', upstream: null },
  ]);
});

test('parses double-NUL-delimited worktree records independently', () => {
  const output = [
    'worktree /repo/one\0HEAD abc123\0branch refs/heads/feature/one\0\0',
    'worktree /repo/two\0HEAD def456\0detached\0\0',
  ].join('');

  assert.deepEqual(parseWorktreeRecords(output), [
    { path: '/repo/one', head: 'abc123', branch: 'feature/one' },
    { path: '/repo/two', head: 'def456', branch: null },
  ]);
});

test('recomputes a capture-generated disposition when evidence becomes dirty', () => {
  assert.deepEqual(reconcileDisposition({
    prior: {
      disposition: 'accounted',
      dispositionSource: 'capture',
      reason: 'No unique commits or dirty work versus origin/main.',
      accountedBy: ['main123'],
      owner: 'Program 0',
    },
    uniqueCommits: [],
    dirty: [' M package.json'],
    mainCommit: 'main123',
  }), {
    disposition: 'unresolved',
    dispositionSource: 'capture',
    reason: null,
    accountedBy: [],
    owner: 'Program 0',
  });
});

test('preserves an explicit human disposition when evidence is recaptured', () => {
  const prior = {
    disposition: 'excluded',
    dispositionSource: 'human',
    reason: 'Approved exclusion.',
    accountedBy: ['decision:1'],
    owner: 'Baah',
  };
  assert.deepEqual(reconcileDisposition({
    prior,
    uniqueCommits: ['abc123'],
    dirty: [' M package.json'],
    mainCommit: 'main123',
  }), prior);
});
