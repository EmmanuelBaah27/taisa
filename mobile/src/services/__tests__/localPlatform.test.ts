import type { PrivateCaptureService } from '../privateCapture';
import { initializeLocalCaptureService } from '../localPlatform';

describe('local capture platform startup', () => {
  test('drains recoverable audio cleanup before exposing the service', async () => {
    const drainAudioCleanupQueue = jest.fn(async () => undefined);
    const service = { drainAudioCleanupQueue } as unknown as PrivateCaptureService;

    await expect(initializeLocalCaptureService(service)).resolves.toBe(service);
    expect(drainAudioCleanupQueue).toHaveBeenCalledTimes(1);
  });

  test('does not expose a service when its durable cleanup queue cannot be opened', async () => {
    const failure = new Error('local cleanup database unavailable');
    const service = {
      drainAudioCleanupQueue: jest.fn(async () => { throw failure; }),
    } as unknown as PrivateCaptureService;

    await expect(initializeLocalCaptureService(service)).rejects.toBe(failure);
  });
});
