import { invalidateLocalCaptureService } from './localPlatform';
import { useCareerStore } from '../stores/careerStore';
import { useChatStore } from '../stores/chatStore';
import { useJournalStore } from '../stores/journalStore';
import { useThreadStore } from '../stores/threadStore';

export interface ReadableStoreAuthorityDependencies {
  clearCareer(): void;
  clearThreads(): void;
  clearChat(): void;
  clearJournal(): void;
  invalidateCapture(): void;
  fetchProfile(): Promise<void>;
  fetchThreads(): Promise<void>;
}

const nativeDependencies: ReadableStoreAuthorityDependencies = {
  clearCareer: () => useCareerStore.getState().clearForAuthorityReplacement(),
  clearThreads: () => useThreadStore.getState().clearForAuthorityReplacement(),
  clearChat: () => useChatStore.getState().clearActiveSession(),
  clearJournal: () => useJournalStore.getState().clearForAuthorityReplacement(),
  invalidateCapture: invalidateLocalCaptureService,
  fetchProfile: () => useCareerStore.getState().fetchProfile(),
  fetchThreads: () => useThreadStore.getState().fetchThreads(),
};

export async function replaceReadableStoreAuthority(
  dependencies: ReadableStoreAuthorityDependencies = nativeDependencies,
): Promise<void> {
  // Clear synchronously before any read can observe values from the replaced authority.
  dependencies.clearCareer();
  dependencies.clearThreads();
  dependencies.clearChat();
  dependencies.clearJournal();
  dependencies.invalidateCapture();
  await Promise.all([dependencies.fetchProfile(), dependencies.fetchThreads()]);
}
