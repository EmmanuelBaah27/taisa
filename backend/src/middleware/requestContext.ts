import { randomUUID } from 'crypto';
import type { ErrorRequestHandler, NextFunction, Request, RequestHandler, Response } from 'express';

declare global {
  namespace Express {
    interface Request {
      requestId?: string;
    }
  }
}

const SAFE_REQUEST_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function resolveRequestId(request: Request): string {
  const supplied = request.header('x-request-id')?.trim();
  return supplied && SAFE_REQUEST_ID.test(supplied) ? supplied : randomUUID();
}

function localStackFrames(): string {
  const stack = new Error().stack;
  if (!stack) return 'stack unavailable';
  const frames = stack.split('\n').slice(2).join('\n').trim();
  return frames || 'stack unavailable';
}

export const requestContext: RequestHandler = (
  request: Request,
  response: Response,
  next: NextFunction,
) => {
  const started = Date.now();
  request.requestId = resolveRequestId(request);
  response.setHeader('x-request-id', request.requestId);

  response.on('finish', () => {
    console.info(
      JSON.stringify({
        requestId: request.requestId,
        method: request.method,
        route: request.originalUrl.split('?')[0],
        status: response.statusCode,
        latencyMs: Date.now() - started,
      }),
    );
  });

  next();
};

export function logRequestError(request: Request, errorCode: string, _error: unknown): void {
  console.error(
    JSON.stringify({
      requestId: request.requestId ?? 'missing-request-id',
      errorCode,
      stack: localStackFrames(),
    }),
  );
}

export const contentSafeErrorHandler: ErrorRequestHandler = (
  error,
  request,
  response,
  _next,
) => {
  logRequestError(request, 'INTERNAL_ERROR', error);
  response.status(500).json({
    success: false,
    error: { code: 'INTERNAL_ERROR', message: 'An internal error occurred' },
  });
};
