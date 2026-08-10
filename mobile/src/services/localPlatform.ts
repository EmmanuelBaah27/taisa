import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';

import { openTaisaDatabase } from '../db/openDatabase';
import { createExpoAudioFileStore } from './audioFileStore';
import { requestCoaching } from './coaching';
import { createPrivateCaptureService, type PrivateCaptureService } from './privateCapture';
import { requestTranscription } from './transcription';

let activeService: Promise<PrivateCaptureService> | null = null;

export function invalidateLocalCaptureService(): void {
  activeService = null;
}

export async function initializeLocalCaptureService(
  service: PrivateCaptureService,
): Promise<PrivateCaptureService> {
  await service.drainAudioCleanupQueue();
  return service;
}

export function getPrivateCaptureService(): Promise<PrivateCaptureService> {
  if (activeService !== null) return activeService;
  activeService = (async () => {
    const database = await openTaisaDatabase();
    const service = createPrivateCaptureService({
      database,
      coach: requestCoaching,
      transcribe: requestTranscription,
      now: () => new Date().toISOString(),
      createId: () => Crypto.randomUUID(),
      audioFiles: createExpoAudioFileStore(),
      async getProfileId() {
        const profileId = await SecureStore.getItemAsync('userId');
        if (profileId === null) throw new Error('Local profile is not initialized');
        return profileId;
      },
    });
    return initializeLocalCaptureService(service);
  })();
  void activeService.catch(() => {
    activeService = null;
  });
  return activeService;
}
