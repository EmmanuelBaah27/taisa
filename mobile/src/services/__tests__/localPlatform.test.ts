import type { PrivateCaptureService } from '../privateCapture';
import {
  createLeasedPrivateCaptureService,
  initializeLocalCaptureService,
} from '../localPlatform';

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

  test('holds the database operation lease until deferred coaching work and final writes complete', async () => {
    let releaseProvider!: () => void;
    const providerGate = new Promise<void>((resolve) => { releaseProvider = resolve; });
    let leaseActive = false;
    const timeline: string[] = [];
    const service = {
      submitText: jest.fn(async () => {
        timeline.push('provider-started');
        await providerGate;
        expect(leaseActive).toBe(true);
        timeline.push('final-write');
        return {
          status: 'completed' as const,
          requestId: 'request-1',
          messageId: 'message-1',
          assistantMessageId: 'assistant-1',
          pendingProposalIds: [],
          pendingProposals: [],
        };
      }),
    } as unknown as PrivateCaptureService;
    const leased = createLeasedPrivateCaptureService(async (work) => {
      leaseActive = true;
      try {
        return await work(service);
      } finally {
        leaseActive = false;
        timeline.push('lease-released');
      }
    });

    const operation = leased.submitText({ conversationId: 'conversation-1', content: 'Help' });
    await Promise.resolve();
    expect(leaseActive).toBe(true);
    expect(timeline).toEqual(['provider-started']);

    releaseProvider();
    await operation;
    expect(leaseActive).toBe(false);
    expect(timeline).toEqual(['provider-started', 'final-write', 'lease-released']);
  });
});
