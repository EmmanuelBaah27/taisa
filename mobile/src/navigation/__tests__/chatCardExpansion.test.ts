import {
  getChatCardInitialTransform,
  isChatCardSourceViewportCurrent,
  parseChatCardFrame,
  parseChatCardSource,
} from '../chatCardExpansion';

describe('chat card expansion geometry', () => {
  test('parses a complete positive card frame from route values', () => {
    expect(parseChatCardFrame({
      cardX: '16',
      cardY: '140',
      cardWidth: '361',
      cardHeight: '72',
    })).toEqual({ x: 16, y: 140, width: 361, height: 72 });
  });

  test('parses the card frame and exact non-negative list scroll offset as one source snapshot', () => {
    expect(parseChatCardSource({
      cardX: '16',
      cardY: '140',
      cardWidth: '361',
      cardHeight: '72',
      listScrollY: '248.5',
      sourceViewportWidth: '393',
      sourceViewportHeight: '852',
    })).toEqual({
      frame: { x: 16, y: 140, width: 361, height: 72 },
      listScrollY: 248.5,
      viewport: { width: 393, height: 852 },
    });
  });

  test.each(['missing', '-1', 'NaN'])('rejects a card source with an invalid list offset', (value) => {
    expect(parseChatCardSource({
      cardX: '16',
      cardY: '140',
      cardWidth: '361',
      cardHeight: '72',
      listScrollY: value === 'missing' ? undefined : value,
      sourceViewportWidth: '393',
      sourceViewportHeight: '852',
    })).toBeNull();
  });

  test.each([
    [{ cardX: '16', cardY: '140', cardWidth: '361' }],
    [{ cardX: 'left', cardY: '140', cardWidth: '361', cardHeight: '72' }],
    [{ cardX: '16', cardY: '140', cardWidth: '0', cardHeight: '72' }],
    [{ cardX: '16', cardY: '140', cardWidth: '361', cardHeight: '-1' }],
  ])('rejects incomplete, malformed, or non-positive card frames', (params) => {
    expect(parseChatCardFrame(params)).toBeNull();
  });

  test('derives the card center offset and independent viewport scales', () => {
    expect(getChatCardInitialTransform(
      { x: 16, y: 140, width: 361, height: 72 },
      { width: 393, height: 852 },
    )).toEqual({
      translateX: 0,
      translateY: -250,
      scaleX: 361 / 393,
      scaleY: 72 / 852,
    });
  });

  test('rejects unusable viewport dimensions', () => {
    expect(getChatCardInitialTransform(
      { x: 16, y: 140, width: 361, height: 72 },
      { width: 0, height: 852 },
    )).toBeNull();
  });

  test('allows reverse morph only while the source viewport is still current', () => {
    const source = {
      frame: { x: 16, y: 140, width: 361, height: 72 },
      listScrollY: 248.5,
      viewport: { width: 393, height: 852 },
    };

    expect(isChatCardSourceViewportCurrent(source, { width: 393, height: 852 })).toBe(true);
    expect(isChatCardSourceViewportCurrent(source, { width: 852, height: 393 })).toBe(false);
  });
});
