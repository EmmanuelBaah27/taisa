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
