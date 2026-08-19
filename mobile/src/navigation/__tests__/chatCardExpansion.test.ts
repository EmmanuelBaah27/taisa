import {
  getChatCardInitialTransform,
  parseChatCardFrame,
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
});
