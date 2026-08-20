import { Router } from 'express';
import type { DeviceCredentialStore } from '../auth/deviceCredentials';

export function createDeviceEnrollmentRouter(store: DeviceCredentialStore) {
  const router = Router();
  router.post('/', (request, response) => {
    const code = typeof request.body?.code === 'string' ? request.body.code : '';
    try {
      const credential = store.enroll(code);
      return response.status(201).json({ success: true, data: credential });
    } catch {
      return response.status(401).json({
        success: false,
        error: { code: 'INVALID_ENROLLMENT_CODE', message: 'Enrollment code is invalid or expired' },
      });
    }
  });
  return router;
}
