import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { normalizeWorktree, parseBranchRecords, parseWorktreeRecords } from './lib.mjs';

function git(args, options = {}) {
  return execFileSync('git', args, {
    cwd: options.cwd,
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
  }).trimEnd();
}

function argument(name, fallback) {
  const prefix = `--${name}=`;
  const value = process.argv.slice(2).find((item) => item.startsWith(prefix));
  return value ? value.slice(prefix.length) : fallback;
}

function localBranches(repositoryRoot) {
  const output = git([
    'for-each-ref',
    '--format=%(refname:short)%00%(objectname)%00%(upstream:short)%00',
    'refs/heads',
  ], { cwd: repositoryRoot });
  return parseBranchRecords(output);
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function uniqueCommits(repositoryRoot, head) {
  const output = git(['rev-list', '--reverse', `origin/main..${head}`], { cwd: repositoryRoot });
  return output ? output.split('\n') : [];
}

async function existingManifest(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

function humanFields(source) {
  return source ? {
    disposition: source.disposition,
    reason: source.reason,
    accountedBy: source.accountedBy,
    owner: source.owner,
  } : {};
}

const repositoryRoot = git(['rev-parse', '--show-toplevel']);
const commonDirectory = resolve(repositoryRoot, git(['rev-parse', '--git-common-dir']));
const candidateRef = argument('candidate', 'origin/preview/taisa');
const candidateCommit = git(['rev-parse', `${candidateRef}^{commit}`], { cwd: repositoryRoot });
const mainCommit = git(['rev-parse', 'origin/main^{commit}'], { cwd: repositoryRoot });
const remotePreviewCommit = git(['rev-parse', 'origin/preview/taisa^{commit}'], { cwd: repositoryRoot });
const manifestPath = resolve(repositoryRoot, 'docs/migration/swiftui/baseline-manifest.json');
const previous = await existingManifest(manifestPath);
const previousByKey = new Map((previous?.sources ?? []).map((source) => [source.key, source]));
const worktrees = parseWorktreeRecords(git(['worktree', 'list', '--porcelain', '-z'], { cwd: repositoryRoot }));
const worktreeByBranch = new Map(worktrees.filter((item) => item.branch).map((item) => [item.branch, item]));

const sources = localBranches(repositoryRoot).map((branchRecord) => {
  const worktree = worktreeByBranch.get(branchRecord.branch);
  const dirty = worktree
    ? git(['status', '--porcelain=v1', '--untracked-files=all'], { cwd: worktree.path }).split('\n').filter(Boolean)
    : [];
  const patch = worktree ? git(['diff', '--binary', 'HEAD'], { cwd: worktree.path }) : '';
  const unique = uniqueCommits(repositoryRoot, branchRecord.head);
  const key = `branch:${branchRecord.branch}`;
  const prior = previousByKey.get(key);
  const defaultDisposition = unique.length || dirty.length ? 'unresolved' : 'accounted';
  return normalizeWorktree({
    key,
    name: branchRecord.branch,
    path: worktree?.path ?? null,
    head: branchRecord.head,
    branch: branchRecord.branch,
    upstream: branchRecord.upstream,
    dirty,
    trackedPatchSha256: patch ? sha256(patch) : null,
    uniqueCommits: unique,
    disposition: prior?.disposition ?? defaultDisposition,
    reason: prior?.reason ?? (defaultDisposition === 'accounted' ? 'No unique commits or dirty work versus origin/main.' : null),
    accountedBy: prior?.accountedBy ?? (defaultDisposition === 'accounted' ? [mainCommit] : []),
    owner: prior?.owner ?? 'Program 0',
    ...humanFields(prior),
  });
});

for (const worktree of worktrees.filter((item) => !item.branch)) {
  const dirty = git(['status', '--porcelain=v1', '--untracked-files=all'], { cwd: worktree.path }).split('\n').filter(Boolean);
  const patch = git(['diff', '--binary', 'HEAD'], { cwd: worktree.path });
  const unique = uniqueCommits(repositoryRoot, worktree.head);
  const key = `detached:${worktree.path}`;
  const prior = previousByKey.get(key);
  sources.push(normalizeWorktree({
    key,
    name: `detached:${basename(worktree.path)}`,
    path: worktree.path,
    head: worktree.head,
    branch: null,
    upstream: null,
    dirty,
    trackedPatchSha256: patch ? sha256(patch) : null,
    uniqueCommits: unique,
    disposition: prior?.disposition ?? (unique.length || dirty.length ? 'unresolved' : 'accounted'),
    reason: prior?.reason ?? null,
    accountedBy: prior?.accountedBy ?? [],
    owner: prior?.owner ?? 'Program 0',
    ...humanFields(prior),
  }));
}

const routeOutput = git(['ls-tree', '-r', '--name-only', candidateCommit, '--', 'mobile/app'], { cwd: repositoryRoot });
const requiredRoutes = routeOutput
  .split('\n')
  .filter((path) => path.endsWith('.tsx') && basename(path) !== '_layout.tsx')
  .sort();

const manifest = {
  schemaVersion: 1,
  status: previous?.status ?? 'candidate',
  capturedAt: new Date().toISOString(),
  repositoryRoot,
  commonDirectory,
  mainCommit,
  remotePreviewCommit,
  candidate: {
    ref: candidateRef,
    commit: candidateCommit,
  },
  requiredRoutes,
  sources: sources.sort((left, right) => left.key.localeCompare(right.key)),
};

await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
process.stdout.write(`Captured ${manifest.sources.length} sources and ${requiredRoutes.length} routes at ${candidateCommit}.\n`);
