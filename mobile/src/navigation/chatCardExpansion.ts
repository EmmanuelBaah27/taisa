export interface ChatCardFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ChatViewport {
  width: number;
  height: number;
}

export interface ChatCardInitialTransform {
  translateX: number;
  translateY: number;
  scaleX: number;
  scaleY: number;
}

type RouteValue = string | string[] | undefined;

export function parseChatCardFrame(params: {
  cardX?: RouteValue;
  cardY?: RouteValue;
  cardWidth?: RouteValue;
  cardHeight?: RouteValue;
}): ChatCardFrame | null {
  const values = [params.cardX, params.cardY, params.cardWidth, params.cardHeight]
    .map((value) => Array.isArray(value) ? value[0] : value)
    .map((value) => value === undefined ? Number.NaN : Number(value));
  const [x, y, width, height] = values;

  if (!values.every(Number.isFinite) || width <= 0 || height <= 0) return null;
  return { x, y, width, height };
}

export function getChatCardInitialTransform(
  frame: ChatCardFrame,
  viewport: ChatViewport,
): ChatCardInitialTransform | null {
  if (viewport.width <= 0 || viewport.height <= 0) return null;

  return {
    translateX: frame.x + frame.width / 2 - viewport.width / 2,
    translateY: frame.y + frame.height / 2 - viewport.height / 2,
    scaleX: Math.min(frame.width / viewport.width, 1),
    scaleY: Math.min(frame.height / viewport.height, 1),
  };
}
