import type { RecordingResult } from './audio';

export type RecordingSubmissionOutcome = 'discard' | 'retain' | 'release';

export interface RecordingSubmissionLease {
  readonly recording: RecordingResult;
  requestCleanup(): void;
  settle(input: {
    succeeded: boolean;
    durableRequestExists: boolean;
    captureStillOpen: boolean;
  }): { outcome: RecordingSubmissionOutcome; recording: RecordingResult };
}

/** Keeps the recorder-cache URI owned until submit either persists it or returns it to the UI. */
export function createRecordingSubmissionLease(
  recording: RecordingResult,
): RecordingSubmissionLease {
  let cleanupRequested = false;
  return {
    recording,
    requestCleanup() {
      cleanupRequested = true;
    },
    settle(input) {
      const outcome: RecordingSubmissionOutcome = cleanupRequested || !input.captureStillOpen
        ? 'discard'
        : input.succeeded || input.durableRequestExists
          ? 'release'
          : 'retain';
      return { outcome, recording };
    },
  };
}
