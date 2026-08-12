import {
  confirmRedactionPreview,
  createRedactionPreview,
  redactSubmission,
} from '../redactSubmission';

describe('submission redaction', () => {
  test('replaces user-selected identifiers deterministically without mutating the selection list', () => {
    const input = 'Ama shipped Atlas for Acme and improved conversion by 24%.';
    const selections = [
      { kind: 'name' as const, start: 0, end: 3 },
      { kind: 'project' as const, start: 12, end: 17 },
      { kind: 'organization' as const, start: 22, end: 26 },
      { kind: 'metric' as const, start: 54, end: 57 },
    ];
    const originalOrder = selections.map(({ start }) => start);

    const result = redactSubmission(input, selections);

    expect(result.text).toBe(
      '[NAME] shipped [PROJECT] for [ORGANIZATION] and improved conversion by [METRIC].',
    );
    expect(result.replacements).toEqual([
      { kind: 'name', start: 0, end: 3, original: 'Ama', token: '[NAME]' },
      { kind: 'project', start: 12, end: 17, original: 'Atlas', token: '[PROJECT]' },
      { kind: 'organization', start: 22, end: 26, original: 'Acme', token: '[ORGANIZATION]' },
      { kind: 'metric', start: 54, end: 57, original: '24%', token: '[METRIC]' },
    ]);
    expect(selections.map(({ start }) => start)).toEqual(originalOrder);
  });

  test('rejects overlapping ranges instead of applying an ambiguous partial redaction', () => {
    expect(() => redactSubmission('Project Atlas', [
      { kind: 'project', start: 0, end: 13 },
      { kind: 'name', start: 8, end: 13 },
    ])).toThrow('Redaction selections overlap');
  });

  test.each([
    [{ kind: 'name' as const, start: -1, end: 2 }, 'outside'],
    [{ kind: 'name' as const, start: 2, end: 2 }, 'non-empty'],
    [{ kind: 'name' as const, start: 1.5, end: 2 }, 'integer'],
    [{ kind: 'name' as const, start: 0, end: 99 }, 'outside'],
  ])('rejects an invalid range %#', (selection, message) => {
    expect(() => redactSubmission('Ama', [selection])).toThrow(message);
  });

  test('rejects ranges that split a Unicode surrogate pair', () => {
    const input = 'Led 🚀 launch';
    expect(() => redactSubmission(input, [
      { kind: 'project', start: 4, end: 5 },
    ])).toThrow('Unicode boundary');
  });

  test('rejects a range that splits a base character from its combining mark', () => {
    const input = 'Cafe\u0301 launch';
    expect(() => redactSubmission(input, [
      { kind: 'project', start: 0, end: 4 },
    ])).toThrow('Unicode boundary');
  });

  test.each([
    ['regional-indicator flag', '🇬🇭 launch', 0, 2],
    ['Hangul jamo syllable', '가 launch', 0, 1],
    ['Indic conjunct', 'क्ष launch', 0, 1],
    ['emoji ZWJ sequence', '👩‍💻 launch', 0, 2],
    ['CRLF pair', 'private\r\nlaunch', 0, 8],
  ])('rejects a range that splits a %s grapheme cluster', (_name, input, start, end) => {
    expect(() => redactSubmission(input, [
      { kind: 'project', start, end },
    ])).toThrow('Unicode boundary');
  });

  test('fails closed when the runtime has no Unicode grapheme segmenter', () => {
    const descriptor = Object.getOwnPropertyDescriptor(Intl, 'Segmenter');
    Object.defineProperty(Intl, 'Segmenter', { configurable: true, value: undefined });
    try {
      expect(() => redactSubmission('Atlas', [
        { kind: 'project', start: 0, end: 5 },
      ])).toThrow('Unicode grapheme validation is unavailable');
    } finally {
      if (descriptor) Object.defineProperty(Intl, 'Segmenter', descriptor);
    }
  });

  test('requires a selected metric to contain a numeric value', () => {
    expect(() => redactSubmission('high growth', [
      { kind: 'metric', start: 0, end: 4 },
    ])).toThrow('numeric');
  });

  test('submits exactly the displayed preview only after an explicit user action', () => {
    const preview = createRedactionPreview('Ama led Atlas', [
      { kind: 'name', start: 0, end: 3 },
      { kind: 'project', start: 8, end: 13 },
    ]);

    expect(preview.text).toBe('[NAME] led [PROJECT]');
    expect(() => confirmRedactionPreview(preview, 'dismiss')).toThrow('explicit');
    expect(confirmRedactionPreview(preview, 'explicit-submit')).toEqual({
      text: preview.text,
    });
  });
});
