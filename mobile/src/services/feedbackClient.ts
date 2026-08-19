import type { FeedbackShareDraft } from './feedbackBundle';
import type { ResponseReaction } from '../repositories/responseFeedbackRepository';

interface FeedbackHttpClient {
  post(path: string, body: unknown): Promise<{ data?: unknown }>;
  delete(path: string): Promise<unknown>;
}

export interface ShareFeedbackInput {
  readonly idempotencyId: string;
  readonly consentedAt: string | null;
  readonly reaction: ResponseReaction;
  readonly note: string | null;
  readonly draft: FeedbackShareDraft;
}

export function createFeedbackClient(http: FeedbackHttpClient) {
  return {
    async share(input: ShareFeedbackInput): Promise<{ receiptId: string }> {
      if (input.consentedAt === null) throw new Error('Explicit consent is required');
      const response = await http.post('/feedback-examples', {
        idempotencyId: input.idempotencyId,
        consentedAt: input.consentedAt,
        example: {
          requestId: input.draft.requestId,
          kind: input.draft.kind,
          stance: input.draft.stance,
          reaction: input.reaction,
          note: input.note,
          userTurn: input.draft.userTurn,
          assistantReply: input.draft.assistantReply,
          contextManifest: input.draft.contextManifest,
          usedContext: input.draft.usedContext,
        },
      });
      const value = response.data as { success?: unknown; data?: { receiptId?: unknown } } | undefined;
      if (value?.success !== true || typeof value.data?.receiptId !== 'string') {
        throw new Error('Feedback sharing failed');
      }
      return { receiptId: value.data.receiptId };
    },
    async remove(receiptId: string): Promise<void> {
      await http.delete(`/feedback-examples/${encodeURIComponent(receiptId)}`);
    },
  };
}
