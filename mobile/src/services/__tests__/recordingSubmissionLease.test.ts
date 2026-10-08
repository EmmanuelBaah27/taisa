import type { RecordingResult } from '../audio';
import { createRecordingSubmissionLease } from '../recordingSubmissionLease';

const RECORDING: RecordingResult = {
  uri: 'file:///cache/submitting-recording.m4a',
  durationSeconds: 15,
};

describe('recording submission ownership', () => {
  test('close during a pre-request failure returns the temp URI for queued cleanup', () => {
    const lease = createRecordingSubmissionLease(RECORDING);
    lease.requestCleanup();

    expect(lease.settle({
      succeeded: false,
      durableRequestExists: false,
      captureStillOpen: false,
    })).toEqual({ outcome: 'discard', recording: RECORDING });
  });

  test('an open capture retains a pre-request failure for explicit retry or replacement', () => {
    const lease = createRecordingSubmissionLease(RECORDING);

    expect(lease.settle({
      succeeded: false,
      durableRequestExists: false,
      captureStillOpen: true,
    })).toEqual({ outcome: 'retain', recording: RECORDING });
  });

  test('a durable request or completed handoff releases UI ownership', () => {
    const failedAfterPersistence = createRecordingSubmissionLease(RECORDING);
    expect(failedAfterPersistence.settle({
      succeeded: false,
      durableRequestExists: true,
      captureStillOpen: true,
    }).outcome).toBe('release');

    const completed = createRecordingSubmissionLease(RECORDING);
    expect(completed.settle({
      succeeded: true,
      durableRequestExists: true,
      captureStillOpen: true,
    }).outcome).toBe('release');
  });
});
