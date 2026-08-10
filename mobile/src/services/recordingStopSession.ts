import type { RecordingResult } from './audio';

interface RecordingStopSessionDependencies {
  stop(): Promise<RecordingResult>;
  discard(uri: string): Promise<void>;
}

export interface RecordingStopSession {
  stopForReview(): Promise<RecordingResult | null>;
  stopAndDiscard(): Promise<void>;
}

export interface RecordingStartGuard {
  begin(): number | null;
  cancel(): void;
  complete(attempt: number): boolean;
}

export function createRecordingStartGuard(): RecordingStartGuard {
  let generation = 0;
  let pending = false;
  return {
    begin() {
      if (pending) return null;
      pending = true;
      generation += 1;
      return generation;
    },
    cancel() {
      generation += 1;
    },
    complete(attempt) {
      pending = false;
      return attempt === generation;
    },
  };
}

/**
 * Owns one active recorder stop. Every caller receives the same stop result,
 * and teardown wins over review when both race for that result.
 */
export function createRecordingStopSession(
  dependencies: RecordingStopSessionDependencies,
): RecordingStopSession {
  let stopPromise: Promise<RecordingResult | null> | null = null;
  let discardPromise: Promise<void> | null = null;
  let discardRequested = false;

  function stopOnce(): Promise<RecordingResult | null> {
    if (stopPromise !== null) return stopPromise;
    stopPromise = dependencies.stop().catch(() => null);
    return stopPromise;
  }

  return {
    async stopForReview() {
      const result = await stopOnce();
      return discardRequested ? null : result;
    },

    stopAndDiscard() {
      discardRequested = true;
      if (discardPromise !== null) return discardPromise;
      discardPromise = (async () => {
        const result = await stopOnce();
        if (result !== null) await dependencies.discard(result.uri);
      })();
      return discardPromise;
    },
  };
}
