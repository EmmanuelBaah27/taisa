import type { LocalConversation, LocalMessage } from '@taisa/shared';

import type {
  CoachingRequestStatus,
  LocalCoachingRequest,
} from '../coachingRequestRepository';
import { insertCoachingRequest } from '../coachingRequestRepository';
import { insertConversation, insertMessage } from '../conversationRepository';
import {
  enqueueAudioCleanup,
  isAudioUriReferencedByActiveCoachingRequest,
  listAudioCleanupQueue,
  listDeletableAudioCleanupQueue,
  markAudioCleanupAttempt,
  removeAudioCleanup,
} from '../audioCleanupRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const AUDIO_URI = 'file:///taisa/audio/request-1.m4a';

describe('audioCleanupRepository', () => {
  test('exact enqueue retry keeps one URI and preserves its existing attempt history', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, { audioUri: AUDIO_URI, enqueuedAt: NOW }),
      );
      await db.withTransaction((tx) =>
        markAudioCleanupAttempt(tx, {
          audioUri: AUDIO_URI,
          attemptedAt: LATER,
          errorCode: 'AUDIO_DELETE_FAILED',
        }),
      );

      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, { audioUri: AUDIO_URI, enqueuedAt: LATER }),
      );

      expect(await listAudioCleanupQueue(db)).toEqual([
        {
          audioUri: AUDIO_URI,
          enqueuedAt: NOW,
          attemptCount: 1,
          lastAttemptAt: LATER,
          lastErrorCode: 'AUDIO_DELETE_FAILED',
        },
      ]);
    } finally {
      db.close();
    }
  });

  test('marks every real cleanup attempt and rejects a readable error as an error code', async () => {
    const db = createTestDatabase();
    const finalAttemptAt = '2026-08-10T11:00:00.000Z';

    try {
      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, { audioUri: AUDIO_URI, enqueuedAt: NOW }),
      );
      await db.withTransaction((tx) =>
        markAudioCleanupAttempt(tx, {
          audioUri: AUDIO_URI,
          attemptedAt: LATER,
          errorCode: 'AUDIO_DELETE_FAILED',
        }),
      );
      await db.withTransaction((tx) =>
        markAudioCleanupAttempt(tx, {
          audioUri: AUDIO_URI,
          attemptedAt: finalAttemptAt,
          errorCode: 'AUDIO_FILE_BUSY',
        }),
      );

      expect((await listAudioCleanupQueue(db))[0]).toEqual({
        audioUri: AUDIO_URI,
        enqueuedAt: NOW,
        attemptCount: 2,
        lastAttemptAt: finalAttemptAt,
        lastErrorCode: 'AUDIO_FILE_BUSY',
      });

      await expect(
        db.withTransaction((tx) =>
          markAudioCleanupAttempt(tx, {
            audioUri: AUDIO_URI,
            attemptedAt: finalAttemptAt,
            errorCode: 'delete failed: confidential recording',
          }),
        ),
      ).rejects.toThrow('Audio cleanup error code must be content-free');
      expect((await listAudioCleanupQueue(db))[0]?.attemptCount).toBe(2);
    } finally {
      db.close();
    }
  });

  test('returns the oldest bounded cleanup batch and enforces the queue limit', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, {
          audioUri: 'file:///taisa/audio/third.m4a',
          enqueuedAt: '2026-08-10T09:00:02.000Z',
        }),
      );
      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, {
          audioUri: 'file:///taisa/audio/first.m4a',
          enqueuedAt: '2026-08-10T09:00:00.000Z',
        }),
      );
      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, {
          audioUri: 'file:///taisa/audio/second.m4a',
          enqueuedAt: '2026-08-10T09:00:01.000Z',
        }),
      );

      expect((await listAudioCleanupQueue(db, 2)).map((entry) => entry.audioUri)).toEqual([
        'file:///taisa/audio/first.m4a',
        'file:///taisa/audio/second.m4a',
      ]);
      await expect(listAudioCleanupQueue(db, 0)).rejects.toThrow(
        'Audio cleanup limit must be between 1 and 50',
      );
      await expect(listAudioCleanupQueue(db, 51)).rejects.toThrow(
        'Audio cleanup limit must be between 1 and 50',
      );
    } finally {
      db.close();
    }
  });

  test('removal is idempotent for an exact cleanup retry', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) =>
        enqueueAudioCleanup(tx, { audioUri: AUDIO_URI, enqueuedAt: NOW }),
      );
      await db.withTransaction((tx) => removeAudioCleanup(tx, AUDIO_URI));
      await db.withTransaction((tx) => removeAudioCleanup(tx, AUDIO_URI));

      expect(await listAudioCleanupQueue(db)).toEqual([]);
    } finally {
      db.close();
    }
  });

  test('detects every audio URI still referenced by a nonterminal coaching request', async () => {
    const db = createTestDatabase();
    const conversation: LocalConversation = {
      id: 'audio-reference-conversation',
      title: null,
      lifecycle: 'active',
      createdAt: NOW,
      updatedAt: NOW,
      archivedAt: null,
    };
    const statuses: readonly CoachingRequestStatus[] = [
      'transcription-pending',
      'transcription-failed',
      'transcript-confirmation-required',
      'coaching-pending',
      'coaching-failed',
      'completed',
      'abandoned',
    ];

    try {
      await db.withTransaction((tx) =>
        insertConversation(tx, conversation, 'audio-reference-conversation-create'),
      );

      for (const [index, status] of statuses.entries()) {
        const id = `audio-reference-${index}`;
        const message: LocalMessage = {
          id: `${id}-message`,
          conversationId: conversation.id,
          parentMessageId: null,
          role: 'user',
          content: 'Submitted voice note',
          lifecycle: status === 'completed' ? 'submitted' : 'pending',
          requestId: id,
          createdAt: NOW,
          updatedAt: NOW,
        };
        const request: LocalCoachingRequest = {
          id,
          intentId: `${id}-intent`,
          conversationId: conversation.id,
          userMessageId: message.id,
          transcriptionRequestId: `${id}-transcription`,
          kind: 'voice',
          status,
          audioUri: `file:///taisa/audio/${status}.m4a`,
          audioDurationSeconds: 12,
          transcriptConfirmedAt: null,
          assistantMessageId: null,
          stance: null,
          contextManifestJson: null,
          errorCode: null,
          attemptCount: 1,
          submittedAt: NOW,
          createdAt: NOW,
          updatedAt: NOW,
        };
        await db.withTransaction(async (tx) => {
          await insertMessage(tx, message, `${id}-message-create`);
          await insertCoachingRequest(tx, request, `${id}-request-create`);
        });
      }

      for (const status of statuses.slice(0, -2)) {
        await expect(
          isAudioUriReferencedByActiveCoachingRequest(
            db,
            `file:///taisa/audio/${status}.m4a`,
          ),
        ).resolves.toBe(true);
      }
      await expect(
        isAudioUriReferencedByActiveCoachingRequest(
          db,
          'file:///taisa/audio/completed.m4a',
        ),
      ).resolves.toBe(false);
      await expect(
        isAudioUriReferencedByActiveCoachingRequest(
          db,
          'file:///taisa/audio/abandoned.m4a',
        ),
      ).resolves.toBe(false);
      await expect(
        isAudioUriReferencedByActiveCoachingRequest(
          db,
          'file:///taisa/audio/not-queued.m4a',
        ),
      ).resolves.toBe(false);
    } finally {
      db.close();
    }
  });

  test('active request audio cannot crowd a deletable path out of a bounded drain batch', async () => {
    const db = createTestDatabase();
    const conversation: LocalConversation = {
      id: 'bounded-drain-conversation',
      title: null,
      lifecycle: 'active',
      createdAt: NOW,
      updatedAt: NOW,
      archivedAt: null,
    };
    const message: LocalMessage = {
      id: 'bounded-drain-message',
      conversationId: conversation.id,
      parentMessageId: null,
      role: 'user',
      content: 'Pending voice note',
      lifecycle: 'pending',
      requestId: 'bounded-drain-request',
      createdAt: NOW,
      updatedAt: NOW,
    };
    const request: LocalCoachingRequest = {
      id: 'bounded-drain-request',
      intentId: 'bounded-drain-intent',
      conversationId: conversation.id,
      userMessageId: message.id,
      transcriptionRequestId: 'bounded-drain-transcription',
      kind: 'voice',
      status: 'transcript-confirmation-required',
      audioUri: AUDIO_URI,
      audioDurationSeconds: 12,
      transcriptConfirmedAt: null,
      assistantMessageId: null,
      stance: null,
      contextManifestJson: null,
      errorCode: null,
      attemptCount: 1,
      submittedAt: NOW,
      createdAt: NOW,
      updatedAt: NOW,
    };
    const deletableUri = 'file:///taisa/audio/deletable-after-active.m4a';

    try {
      await db.withTransaction(async (tx) => {
        await insertConversation(tx, conversation, 'bounded-drain-conversation-create');
        await insertMessage(tx, message, 'bounded-drain-message-create');
        await insertCoachingRequest(tx, request, 'bounded-drain-request-create');
        await enqueueAudioCleanup(tx, { audioUri: AUDIO_URI, enqueuedAt: NOW });
        await enqueueAudioCleanup(tx, { audioUri: deletableUri, enqueuedAt: LATER });
      });

      expect(await listDeletableAudioCleanupQueue(db, 1)).toEqual([
        expect.objectContaining({ audioUri: deletableUri }),
      ]);
      expect(await listAudioCleanupQueue(db, 1)).toEqual([
        expect.objectContaining({ audioUri: AUDIO_URI }),
      ]);
    } finally {
      db.close();
    }
  });

  test('a repeatedly failing old path cannot starve a fresh deletable path', async () => {
    const db = createTestDatabase();
    const oldUri = 'file:///taisa/audio/permanent-failure.m4a';
    const freshUri = 'file:///taisa/audio/fresh-cleanup.m4a';

    try {
      await db.withTransaction(async (tx) => {
        await enqueueAudioCleanup(tx, { audioUri: oldUri, enqueuedAt: NOW });
        await enqueueAudioCleanup(tx, { audioUri: freshUri, enqueuedAt: LATER });
        await markAudioCleanupAttempt(tx, {
          audioUri: oldUri,
          attemptedAt: LATER,
          errorCode: 'AUDIO_DELETE_FAILED',
        });
      });

      expect(await listDeletableAudioCleanupQueue(db, 1)).toEqual([
        expect.objectContaining({ audioUri: freshUri, attemptCount: 0 }),
      ]);
    } finally {
      db.close();
    }
  });
});
