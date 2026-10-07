import { pathToFileURL } from 'node:url';

const canonicalOrigin = 'https://github.com/EmmanuelBaah27/taisa';

export function isCanonicalTaisaOrigin(origin) {
  return origin.replace(/\.git$/, '').replace(/\/$/, '') === canonicalOrigin;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = isCanonicalTaisaOrigin(process.argv[2] ?? '') ? 0 : 1;
}
