import {
  CHAT_CARD_PRESSED_SCALE,
  CHAT_SHEET_DISMISS_DURATION,
  CHAT_SHEET_RETURN_SPRING,
  getResistedChatSheetTranslation,
  getChatCardMotionTimeline,
  getClosingChatShellOpacity,
  getChatCardInitialTransform,
  getTabSurfaceChatTransition,
  isChatCardSourceViewportCurrent,
  parseChatCardFrame,
  parseChatCardSource,
  shouldDismissChatSheet,
} from '../chatCardExpansion';

describe('chat card expansion geometry', () => {
  test('scales the destination page back on open but restores it immediately on close', () => {
    expect(getTabSurfaceChatTransition(true)).toBe('spring-open');
    expect(getTabSurfaceChatTransition(false)).toBe('immediate-close');
  });

  test('dismisses a top-anchored chat sheet by distance or downward velocity', () => {
    expect(shouldDismissChatSheet({ atTop: true, translationY: 121, velocityY: 0 })).toBe(true);
    expect(shouldDismissChatSheet({ atTop: true, translationY: 24, velocityY: 901 })).toBe(true);
    expect(shouldDismissChatSheet({ atTop: true, translationY: 80, velocityY: 300 })).toBe(false);
  });

  test('never dismisses while the conversation is scrolled away from the top', () => {
    expect(shouldDismissChatSheet({ atTop: false, translationY: 300, velocityY: 1400 })).toBe(false);
  });

  test('adds weight to downward sheet travel and uses a slower damped settlement', () => {
    expect(getResistedChatSheetTranslation(-20)).toBe(0);
    expect(getResistedChatSheetTranslation(100)).toBeCloseTo(55);
    expect(CHAT_SHEET_DISMISS_DURATION).toBeGreaterThanOrEqual(360);
    expect(CHAT_SHEET_RETURN_SPRING).toMatchObject({
      damping: 32,
      stiffness: 240,
      overshootClamping: true,
    });
  });

  test('hands the pressed card into a fast overlapping expansion and fade', () => {
    expect(CHAT_CARD_PRESSED_SCALE).toBe(0.97);
    expect(getChatCardMotionTimeline(false)).toEqual({
      openDuration: 240,
      shellFadeDuration: 120,
      shellInitialOpacity: 0.92,
      contentRevealDelay: 40,
      contentRevealDuration: 140,
    });
  });

  test('the closing white shell reveals the real card during the final quarter', () => {
    expect(getClosingChatShellOpacity(0)).toBe(1);
    expect(getClosingChatShellOpacity(0.75)).toBe(1);
    expect(getClosingChatShellOpacity(0.875)).toBe(0.5);
    expect(getClosingChatShellOpacity(1)).toBe(0);
  });

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
