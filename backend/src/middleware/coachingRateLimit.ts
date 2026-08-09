import { createHash } from 'crypto';
import rateLimit from 'express-rate-limit';
import type { Request } from 'express';

function deviceRateLimitKey(request: Request): string {
  const header = request.headers['x-user-id'];
  const deviceId = (Array.isArray(header) ? header[0] : header)?.trim() || 'missing-device-id';
  return `device:${createHash('sha256').update(deviceId).digest('hex')}`;
}

export const coachingRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: deviceRateLimitKey,
  message: {
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many requests, please wait a moment.' },
  },
});
