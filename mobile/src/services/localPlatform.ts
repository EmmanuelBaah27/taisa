import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';

import { openTaisaDatabase } from '../db/openDatabase';
import { requestCoaching } from './coaching';
import { createPrivateCaptureService, type PrivateCaptureService } from './privateCapture';
import { requestTranscription } from './transcription';

let activeService: Promise<PrivateCaptureService> | null = null;

export function getPrivateCaptureService(): Promise<PrivateCaptureService> {
  if (activeService !== null) return activeService;
  activeService = (async () => {
    const database = await openTaisaDatabase();
    return createPrivateCaptureService({
      database,
      coach: requestCoaching,
      transcribe: requestTranscription,
      now: () => new Date().toISOString(),
      createId: () => Crypto.randomUUID(),
      async getProfileId() {
        const profileId = await SecureStore.getItemAsync('userId');
        if (profileId === null) throw new Error('Local profile is not initialized');
        return profileId;
      },
    });
  })();
  void activeService.catch(() => {
    activeService = null;
  });
  return activeService;
}
