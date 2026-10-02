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

export function parseBranchRecords(output) {
  return output
    .split('\n')
    .filter(Boolean)
    .map((record) => {
      const [branch, head, upstream] = record.split('\0');
      return { branch, head, upstream: upstream || null };
    });
}

export function parseWorktreeRecords(output) {
  return output
    .split('\0\0')
    .filter(Boolean)
    .map((record) => {
      const fields = Object.fromEntries(record.split('\0').map((line) => {
        const separator = line.indexOf(' ');
        return separator === -1 ? [line, true] : [line.slice(0, separator), line.slice(separator + 1)];
      }));
      return {
        path: fields.worktree,
        head: fields.HEAD,
        branch: typeof fields.branch === 'string' ? fields.branch.replace('refs/heads/', '') : null,
      };
    });
}

export function reconcileDisposition({ prior, uniqueCommits, dirty, mainCommit }) {
  if (prior?.dispositionSource === 'human') {
    return {
      disposition: prior.disposition,
      dispositionSource: 'human',
      reason: prior.reason,
      accountedBy: prior.accountedBy,
      owner: prior.owner,
    };
  }
  const disposition = uniqueCommits.length || dirty.length ? 'unresolved' : 'accounted';
  return {
    disposition,
    dispositionSource: 'capture',
    reason: disposition === 'accounted' ? 'No unique commits or dirty work versus origin/main.' : null,
    accountedBy: disposition === 'accounted' ? [mainCommit] : [],
    owner: 'Program 0',
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
