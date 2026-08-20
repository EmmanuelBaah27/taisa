import type { NextFunction, Request, Response } from 'express';
import type { DeviceCredentialStore } from '../auth/deviceCredentials';

export function createDeviceAuthentication(store: DeviceCredentialStore) {
  return (request: Request, response: Response, next: NextFunction) => {
    const authorization = request.headers.authorization;
    const token = authorization?.startsWith('Bearer ') ? authorization.slice(7) : '';
    const credentialId = store.authenticate(token);
    if (!credentialId) {
      return response.status(401).json({
        success: false,
        error: { code: 'DEVICE_AUTHENTICATION_REQUIRED', message: 'Device authentication required' },
      });
    }
    response.locals.deviceCredentialId = credentialId;
    return next();
  };
}
