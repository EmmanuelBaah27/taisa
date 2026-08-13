import { buildFeedbackPreview } from '../feedbackBundle';
import { createTestDatabase, NOW } from '../../repositories/__tests__/testDatabase';

test('builds a bounded preview from the exact request and excludes unrelated local data', async () => {
  const db = createTestDatabase();
  try {
    await db.runAsync(`INSERT INTO conversations
      (id, lifecycle, preferred_input_mode, created_at, updated_at)
      VALUES ('c1', 'active', 'voice', $now, $now), ('other', 'active', 'text', $now, $now)`, { $now: NOW });
    await db.runAsync(`INSERT INTO messages
      (id, conversation_id, role, content, lifecycle, request_id, created_at, updated_at)
      VALUES
      ('u1', 'c1', 'user', 'Discuss Project Cedar with Morgan', 'submitted', 'r1', $now, $now),
      ('a1', 'c1', 'assistant', 'Ask what outcome the meeting needs.', 'received', NULL, $now, $now),
      ('secret', 'other', 'user', 'UNRELATED_PRIVATE_SECRET', 'private', NULL, $now, $now)`, { $now: NOW });
    await db.runAsync(`INSERT INTO coaching_requests
      (id, intent_id, conversation_id, user_message_id, kind, status, assistant_message_id,
        transcription_request_id, audio_duration_seconds, stance, context_manifest_json,
        attempt_count, submitted_at, created_at, updated_at)
      VALUES ('r1', 'i1', 'c1', 'u1', 'voice', 'completed', 'a1', 'transcription-1', 12,
        'challenge', '{"includedMemoryIds":["m1"],"excluded":{"audio":true}}',
        1, $now, $now, $now)`,
    { $now: NOW });

    const preview = await buildFeedbackPreview(db, 'a1', {
      userTurn: [{ kind: 'project', start: 8, end: 21 }, { kind: 'name', start: 27, end: 33 }],
      assistantReply: [],
    });

    expect(preview).toEqual({
      responseMessageId: 'a1',
      requestId: 'r1',
      kind: 'voice',
      stance: 'challenge',
      userTurn: 'Discuss [PROJECT] with [NAME]',
      assistantReply: 'Ask what outcome the meeting needs.',
      contextManifest: { includedMemoryIds: ['m1'], excluded: { audio: true } },
      consentRequired: true,
    });
    expect(JSON.stringify(preview)).not.toContain('UNRELATED_PRIVATE_SECRET');
    expect(JSON.stringify(preview)).not.toMatch(/audio_uri|transcript_confirmed_at/i);
  } finally {
    db.close();
  }
});
