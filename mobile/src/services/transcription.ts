import { getDeviceCredential } from './deviceEnrollment';
import { getInstallationId } from './installationIdentity';
import { mobileApiConfig } from './mobileApiConfig';
import {
  createStreamingTranscriptionClient,
  TranscriptionClientError,
} from './streamingTranscription';

export type {
  StreamingTranscriptionRequest,
  StreamingTranscriptionSubscription,
} from './streamingTranscription';
export { TranscriptionClientError };

export const requestStreamingTranscription = createStreamingTranscriptionClient({
  createRequest: () => new XMLHttpRequest(),
  getInstallationId,
  getDeviceCredential,
  baseUrl: mobileApiConfig.baseUrl,
});
