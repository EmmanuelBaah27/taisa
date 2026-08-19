export interface ChatCardFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ChatCardSource {
  frame: ChatCardFrame;
  listScrollY: number;
  viewport: ChatViewport;
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

function parseRouteNumber(value: RouteValue): number {
  const candidate = Array.isArray(value) ? value[0] : value;
  return candidate === undefined || candidate.trim().length === 0
    ? Number.NaN
    : Number(candidate);
}

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

export function parseChatCardSource(params: {
  cardX?: RouteValue;
  cardY?: RouteValue;
  cardWidth?: RouteValue;
  cardHeight?: RouteValue;
  listScrollY?: RouteValue;
  sourceViewportWidth?: RouteValue;
  sourceViewportHeight?: RouteValue;
}): ChatCardSource | null {
  const frame = parseChatCardFrame(params);
  const listScrollY = parseRouteNumber(params.listScrollY);
  const width = parseRouteNumber(params.sourceViewportWidth);
  const height = parseRouteNumber(params.sourceViewportHeight);
  if (
    frame === null ||
    !Number.isFinite(listScrollY) || listScrollY < 0 ||
    !Number.isFinite(width) || width <= 0 ||
    !Number.isFinite(height) || height <= 0
  ) return null;
  return { frame, listScrollY, viewport: { width, height } };
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

export function isChatCardSourceViewportCurrent(
  source: ChatCardSource,
  viewport: ChatViewport,
): boolean {
  return Math.abs(source.viewport.width - viewport.width) <= 1 &&
    Math.abs(source.viewport.height - viewport.height) <= 1;
}

export function getClosingChatShellOpacity(progress: number): number {
  'worklet';
  const normalized = Math.min(Math.max(progress, 0), 1);
  if (normalized <= 0.75) return 1;
  return (1 - normalized) / 0.25;
}
