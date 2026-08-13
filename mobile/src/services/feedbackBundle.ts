import type { RepositoryConnection } from '../db/types';
import type { RedactionSelection } from './redactSubmission';
import { redactSubmission } from './redactSubmission';

export interface FeedbackRedactions {
  readonly userTurn: readonly RedactionSelection[];
  readonly assistantReply: readonly RedactionSelection[];
}

export interface FeedbackShareDraft {
  readonly responseMessageId: string;
  readonly requestId: string;
  readonly kind: 'text' | 'voice';
  readonly stance: 'mirror' | 'nudge' | 'challenge' | 'direct' | null;
  readonly userTurn: string;
  readonly assistantReply: string;
  readonly contextManifest: Readonly<Record<string, unknown>>;
  readonly consentRequired: true;
}

interface FeedbackSourceRow {
  response_message_id: string;
  request_id: string;
  kind: 'text' | 'voice';
  stance: FeedbackShareDraft['stance'];
  user_turn: string;
  assistant_reply: string;
  context_manifest_json: string | null;
}

function parseManifest(serialized: string | null): Readonly<Record<string, unknown>> {
  if (serialized === null || serialized.length > 20_000) return {};
  try {
    const parsed: unknown = JSON.parse(serialized);
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? parsed as Readonly<Record<string, unknown>>
      : {};
  } catch {
    return {};
  }
}

export async function buildFeedbackPreview(
  database: RepositoryConnection,
  responseMessageId: string,
  redactions: FeedbackRedactions = { userTurn: [], assistantReply: [] },
): Promise<FeedbackShareDraft> {
  const row = await database.getFirstAsync<FeedbackSourceRow>(
    `SELECT assistant.id AS response_message_id, request.id AS request_id,
      request.kind, request.stance, user.content AS user_turn,
      assistant.content AS assistant_reply, request.context_manifest_json
     FROM coaching_requests request
     JOIN messages user ON user.id = request.user_message_id
     JOIN messages assistant ON assistant.id = request.assistant_message_id
     WHERE assistant.id = $responseMessageId
       AND assistant.role = 'assistant' AND request.status = 'completed'`,
    { $responseMessageId: responseMessageId },
  );
  if (row === null) throw new Error('Response is unavailable for feedback');
  return {
    responseMessageId: row.response_message_id,
    requestId: row.request_id,
    kind: row.kind,
    stance: row.stance,
    userTurn: redactSubmission(row.user_turn, redactions.userTurn).text,
    assistantReply: redactSubmission(row.assistant_reply, redactions.assistantReply).text,
    contextManifest: parseManifest(row.context_manifest_json),
    consentRequired: true,
  };
}
