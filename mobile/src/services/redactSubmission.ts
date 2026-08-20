export type RedactionKind = 'name' | 'organization' | 'project' | 'metric';

export interface RedactionSelection {
  readonly kind: RedactionKind;
  readonly start: number;
  readonly end: number;
}

export interface RedactionReplacement extends RedactionSelection {
  readonly original: string;
  readonly token: string;
}

export interface RedactionResult {
  readonly text: string;
  /** Kept by the caller in memory only. Never persist or send this map. */
  readonly replacements: readonly RedactionReplacement[];
}

export interface RedactionPreview extends RedactionResult {
  readonly status: 'preview';
}

export interface ConfirmedRedactedSubmission {
  readonly text: string;
}

export type RedactionPreviewAction = 'explicit-submit' | 'dismiss';

interface GraphemeSegment {
  readonly index: number;
}

interface GraphemeSegmenter {
  segment(input: string): Iterable<GraphemeSegment>;
}

function graphemeBoundaries(input: string): ReadonlySet<number> {
  const Segmenter = (Intl as unknown as {
    Segmenter?: new (
      locale?: string,
      options?: { granularity: 'grapheme' },
    ) => GraphemeSegmenter;
  }).Segmenter;
  if (typeof Segmenter !== 'function') {
    throw new Error('Unicode grapheme validation is unavailable');
  }
  const boundaries = new Set<number>([input.length]);
  for (const segment of new Segmenter('und', { granularity: 'grapheme' }).segment(input)) {
    boundaries.add(segment.index);
  }
  return boundaries;
}

function validateSelection(
  input: string,
  selection: RedactionSelection,
  boundaries: ReadonlySet<number>,
): void {
  if (!Number.isInteger(selection.start) || !Number.isInteger(selection.end)) {
    throw new Error('Redaction range boundaries must be integer offsets');
  }
  if (selection.start < 0 || selection.end > input.length) {
    throw new Error('Redaction range is outside the submitted text');
  }
  if (selection.start >= selection.end) {
    throw new Error('Redaction range must select non-empty text');
  }
  if (!boundaries.has(selection.start) || !boundaries.has(selection.end)) {
    throw new Error('Redaction range must end on a Unicode boundary');
  }
  const original = input.slice(selection.start, selection.end);
  if (original.trim().length === 0) {
    throw new Error('Redaction range must contain visible text');
  }
  if (selection.kind === 'metric' && !/\p{Number}/u.test(original)) {
    throw new Error('A metric redaction must contain a numeric value');
  }
}

export function redactSubmission(
  input: string,
  selections: readonly RedactionSelection[],
): RedactionResult {
  const ordered = selections.map((selection) => ({ ...selection }))
    .sort((left, right) => left.start - right.start || left.end - right.end);

  const boundaries = ordered.length === 0 ? new Set([0, input.length]) : graphemeBoundaries(input);
  for (const selection of ordered) validateSelection(input, selection, boundaries);
  for (let index = 1; index < ordered.length; index += 1) {
    if (ordered[index - 1].end > ordered[index].start) {
      throw new Error('Redaction selections overlap');
    }
  }

  const replacements = ordered.map((selection): RedactionReplacement => ({
    ...selection,
    original: input.slice(selection.start, selection.end),
    token: `[${selection.kind.toUpperCase()}]`,
  }));

  const text = [...replacements]
    .sort((left, right) => right.start - left.start)
    .reduce(
      (current, replacement) => (
        current.slice(0, replacement.start)
        + replacement.token
        + current.slice(replacement.end)
      ),
      input,
    );

  return { text, replacements };
}

export function createRedactionPreview(
  input: string,
  selections: readonly RedactionSelection[],
): RedactionPreview {
  return { ...redactSubmission(input, selections), status: 'preview' };
}

export function confirmRedactionPreview(
  preview: RedactionPreview,
  action: RedactionPreviewAction,
): ConfirmedRedactedSubmission {
  if (action !== 'explicit-submit') {
    throw new Error('Redacted text requires an explicit submit action');
  }
  return { text: preview.text };
}
