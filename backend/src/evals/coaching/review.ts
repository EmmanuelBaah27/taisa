import { readFileSync, writeFileSync } from 'fs';
import {
  COACHING_EVALUATION_THRESHOLDS,
  validateCompletedManualReview,
  type CompletedManualReview,
} from './run';

export { validateCompletedManualReview } from './run';
export type { CompletedManualReview } from './run';

export interface ReviewCliIo {
  readFile: (path: string) => string;
  writeFile: (path: string, output: string, options: { flag: 'wx' }) => void;
  writeStderr: (output: string) => void;
}

const defaultReviewCliIo: ReviewCliIo = {
  readFile: (target) => readFileSync(target, 'utf8'),
  writeFile: (target, output, options) => writeFileSync(target, output, options),
  writeStderr: (output) => process.stderr.write(output),
};

function parseExactFlags(argv: string[], names: readonly string[]): Record<string, string> {
  if (argv.length !== names.length) throw new Error('Invalid review arguments');
  const allowed = new Set(names);
  const values: Record<string, string> = {};
  for (const argument of argv) {
    const separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator < 3) throw new Error('Invalid review argument');
    const name = argument.slice(2, separator);
    const value = argument.slice(separator + 1);
    if (!allowed.has(name) || name in values || value.length === 0) {
      throw new Error('Invalid review argument');
    }
    values[name] = value;
  }
  if (names.some((name) => !(name in values))) throw new Error('Missing review argument');
  return values;
}

export function runReviewCli(argv: string[], io: ReviewCliIo = defaultReviewCliIo): 0 | 1 {
  try {
    const flags = parseExactFlags(argv, ['artifact', 'completed-review', 'decision-output']);
    const artifact = JSON.parse(io.readFile(flags.artifact));
    const reviews = JSON.parse(io.readFile(flags['completed-review'])) as readonly CompletedManualReview[];
    const decision = validateCompletedManualReview(artifact, reviews);
    io.writeFile(flags['decision-output'], `${JSON.stringify({
      provider: decision.provider,
      packVersion: decision.packVersion,
      thresholds: COACHING_EVALUATION_THRESHOLDS,
      automatedPassed: decision.automatedPassed,
      manualPassed: decision.manualPassed,
      passed: decision.passed,
    }, null, 2)}\n`, { flag: 'wx' });
    if (!decision.passed) {
      io.writeStderr('EVAL_COACHING_REVIEW_FAILED\n');
      return 1;
    }
    return 0;
  } catch {
    io.writeStderr('EVAL_COACHING_REVIEW_FAILED\n');
    return 1;
  }
}

if (require.main === module) {
  process.exitCode = runReviewCli(process.argv.slice(2));
}
