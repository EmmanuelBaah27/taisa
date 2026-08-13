import * as Crypto from 'expo-crypto';
import type { SQLiteDatabase } from 'expo-sqlite';

import { withTaisaDatabase } from '../db/openDatabase';
import { listProfiles } from '../repositories/profileRepository';
import { createExpoAudioFileStore } from './audioFileStore';
import { requestCoaching } from './coaching';
import { createPrivateCaptureService, type PrivateCaptureService } from './privateCapture';
import { requestTranscription } from './transcription';

type WithCaptureService = <T>(
  work: (service: PrivateCaptureService) => Promise<T>,
) => Promise<T>;

/** Every public operation remains inside its database lease, including paid/transcription waits. */
export function createLeasedPrivateCaptureService(
  withService: WithCaptureService,
): PrivateCaptureService {
  return {
    savePrivateDraft: (input) => withService((service) => service.savePrivateDraft(input)),
    submitText: (input) => withService((service) => service.submitText(input)),
    submitVoice: (input) => withService((service) => service.submitVoice(input)),
    submitVoiceAndCoach: (input) => withService((service) => service.submitVoiceAndCoach(input)),
    reviseSubmittedTranscript: (input) => withService((service) => service.reviseSubmittedTranscript(input)),
    updateTranscript: (input) => withService((service) => service.updateTranscript(input)),
    confirmTranscript: (input) => withService((service) => service.confirmTranscript(input)),
    retrySubmission: (requestId) => withService((service) => service.retrySubmission(requestId)),
    confirmProposal: (input) => withService((service) => service.confirmProposal(input)),
    resolveClarification: (input) => withService((service) => service.resolveClarification(input)),
    hydrateConversation: (conversationId) => (
      withService((service) => service.hydrateConversation(conversationId))
    ),
    setPreferredInputMode: (input) => withService((service) => service.setPreferredInputMode(input)),
    drainAudioCleanupQueue: () => withService((service) => service.drainAudioCleanupQueue()),
    discardRecording: (uri) => withService((service) => service.discardRecording(uri)),
    abandonVoiceSubmission: (requestId) => (
      withService((service) => service.abandonVoiceSubmission(requestId))
    ),
  };
}

export async function initializeLocalCaptureService(
  service: PrivateCaptureService,
): Promise<PrivateCaptureService> {
  await service.drainAudioCleanupQueue();
  return service;
}

let servicesByDatabase = new WeakMap<SQLiteDatabase, Promise<PrivateCaptureService>>();

function getServiceForDatabase(database: SQLiteDatabase): Promise<PrivateCaptureService> {
  const existing = servicesByDatabase.get(database);
  if (existing !== undefined) return existing;
  const opening = (async () => {
    const service = createPrivateCaptureService({
      database,
      coach: requestCoaching,
      transcribe: requestTranscription,
      now: () => new Date().toISOString(),
      createId: () => Crypto.randomUUID(),
      audioFiles: createExpoAudioFileStore(),
      async getProfileId() {
        const profiles = await listProfiles(database);
        if (profiles.length !== 1) {
          throw new Error('The local profile archive must contain exactly one profile.');
        }
        return profiles[0].id;
      },
    });
    return initializeLocalCaptureService(service);
  })();
  servicesByDatabase.set(database, opening);
  void opening.catch(() => { servicesByDatabase.delete(database); });
  return opening;
}

const leasedCaptureService = createLeasedPrivateCaptureService(
  (work) => withTaisaDatabase(async (database) => work(await getServiceForDatabase(database))),
);

// Existing callers may retain this facade safely; it never retains a database handle.
export function invalidateLocalCaptureService(): void {
  servicesByDatabase = new WeakMap<SQLiteDatabase, Promise<PrivateCaptureService>>();
}

export async function getPrivateCaptureService(): Promise<PrivateCaptureService> {
  return leasedCaptureService;
}
