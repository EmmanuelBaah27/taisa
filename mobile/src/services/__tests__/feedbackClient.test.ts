import { createFeedbackClient } from '../feedbackClient';

const draft = {
  responseMessageId: 'assistant-1',
  requestId: 'request-1',
  kind: 'text' as const,
  stance: 'nudge' as const,
  userTurn: 'Synthetic user turn',
  assistantReply: 'Synthetic reply',
  contextManifest: {},
  usedContext: [],
  consentRequired: true as const,
};

test('uploads only after explicit consent and returns an opaque receipt', async () => {
  const post = jest.fn().mockResolvedValue({ data: { success: true, data: { receiptId: 'receipt-1' } } });
  const client = createFeedbackClient({ post, delete: jest.fn() });
  await expect(client.share({
    idempotencyId: 'attempt-1',
    consentedAt: '2026-08-13T15:00:00.000Z',
    reaction: 'helpful',
    note: null,
    draft,
  })).resolves.toEqual({ receiptId: 'receipt-1' });
  expect(post).toHaveBeenCalledTimes(1);
});

test('refuses upload without an explicit consent timestamp', async () => {
  const post = jest.fn();
  const client = createFeedbackClient({ post, delete: jest.fn() });
  await expect(client.share({
    idempotencyId: 'attempt-1', consentedAt: null, reaction: 'helpful', note: null, draft,
  })).rejects.toThrow('Explicit consent is required');
  expect(post).not.toHaveBeenCalled();
});
