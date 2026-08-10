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

function isHighSurrogate(codeUnit: number): boolean {
  return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
}

function isLowSurrogate(codeUnit: number): boolean {
  return codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
}

function splitsSurrogatePair(input: string, index: number): boolean {
  if (index <= 0 || index >= input.length) return false;
  return isHighSurrogate(input.charCodeAt(index - 1)) && isLowSurrogate(input.charCodeAt(index));
}

function isVariationSelector(codePoint: number): boolean {
  return (codePoint >= 0xfe00 && codePoint <= 0xfe0f)
    || (codePoint >= 0xe0100 && codePoint <= 0xe01ef);
}

function isEmojiModifier(codePoint: number): boolean {
  return codePoint >= 0x1f3fb && codePoint <= 0x1f3ff;
}

function splitsUnicodeCluster(input: string, index: number): boolean {
  if (splitsSurrogatePair(input, index)) return true;
  if (index <= 0 || index >= input.length) return false;

  const nextCodePoint = input.codePointAt(index);
  const previousCodePoint = input.codePointAt(index - 1);
  const nextCharacter = String.fromCodePoint(nextCodePoint ?? 0);

  return /^\p{Mark}$/u.test(nextCharacter)
    || (nextCodePoint !== undefined && isVariationSelector(nextCodePoint))
    || (nextCodePoint !== undefined && isEmojiModifier(nextCodePoint))
    || nextCodePoint === 0x200d
    || previousCodePoint === 0x200d;
}

function validateSelection(input: string, selection: RedactionSelection): void {
  if (!Number.isInteger(selection.start) || !Number.isInteger(selection.end)) {
    throw new Error('Redaction range boundaries must be integer offsets');
  }
  if (selection.start < 0 || selection.end > input.length) {
    throw new Error('Redaction range is outside the submitted text');
  }
  if (selection.start >= selection.end) {
    throw new Error('Redaction range must select non-empty text');
  }
  if (splitsUnicodeCluster(input, selection.start) || splitsUnicodeCluster(input, selection.end)) {
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

  for (const selection of ordered) validateSelection(input, selection);
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
