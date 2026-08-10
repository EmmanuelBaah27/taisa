import type { RecordingResult } from '../audio';
import {
  createRecordingStartGuard,
  createRecordingStopSession,
} from '../recordingStopSession';

const RESULT: RecordingResult = {
  uri: 'file:///cache/active-recording.m4a',
  durationSeconds: 12,
};

describe('recording stop session', () => {
  test('a keyboard cancellation while recorder start is pending invalidates that start attempt', () => {
    const guard = createRecordingStartGuard();
    const attempt = guard.begin();

    expect(attempt).not.toBeNull();
    expect(guard.begin()).toBeNull();
    guard.cancel();

    expect(guard.complete(attempt!)).toBe(false);
    expect(guard.begin()).not.toBeNull();
  });

  test('retains the stop result for explicit review', async () => {
    const stop = jest.fn(async () => RESULT);
    const discard = jest.fn(async (_uri: string) => undefined);
    const session = createRecordingStopSession({ stop, discard });

    await expect(session.stopForReview()).resolves.toEqual(RESULT);
    expect(stop).toHaveBeenCalledTimes(1);
    expect(discard).not.toHaveBeenCalled();
  });

  test('close and unmount share one stop and one retained-uri cleanup', async () => {
    let releaseStop!: (result: RecordingResult) => void;
    const stop = jest.fn(() => new Promise<RecordingResult>((resolve) => {
      releaseStop = resolve;
    }));
    const discard = jest.fn(async (_uri: string) => undefined);
    const session = createRecordingStopSession({ stop, discard });

    const close = session.stopAndDiscard();
    const unmount = session.stopAndDiscard();
    releaseStop(RESULT);

    await Promise.all([close, unmount]);
    expect(stop).toHaveBeenCalledTimes(1);
    expect(discard).toHaveBeenCalledTimes(1);
    expect(discard).toHaveBeenCalledWith(RESULT.uri);
  });

  test('a cleanup racing a manual stop prevents the result becoming review state', async () => {
    let releaseStop!: (result: RecordingResult) => void;
    const stop = jest.fn(() => new Promise<RecordingResult>((resolve) => {
      releaseStop = resolve;
    }));
    const discard = jest.fn(async (_uri: string) => undefined);
    const session = createRecordingStopSession({ stop, discard });

    const review = session.stopForReview();
    const cleanup = session.stopAndDiscard();
    releaseStop(RESULT);

    await expect(review).resolves.toBeNull();
    await cleanup;
    expect(discard).toHaveBeenCalledWith(RESULT.uri);
  });

  test('a stop failure has no URI to lose and does not invoke deletion', async () => {
    const stop = jest.fn(async () => {
      throw new Error('No active recording');
    });
    const discard = jest.fn(async (_uri: string) => undefined);
    const session = createRecordingStopSession({ stop, discard });

    await expect(session.stopAndDiscard()).resolves.toBeUndefined();
    expect(discard).not.toHaveBeenCalled();
  });
});
