import { Router } from 'express';
import { z } from 'zod';
import { startSession, sendMessage, getMessages } from '../services/claude/chatAgent';
import { getDb } from '../db/connection';
import { parseAnthropicError } from '../services/claude/client';

const router = Router();

function requireUserId(req: any, res: any): string | null {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) {
    res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });
    return null;
  }
  return userId;
}

// POST /api/v1/chat/session/start
const StartSessionSchema = z.object({
  entryId: z.string().optional().nullable(),
});

router.post('/session/start', async (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  const parsed = StartSessionSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.message } });
  }

  try {
    const sessionId = await startSession({ userId, entryId: parsed.data.entryId ?? null });
    res.status(201).json({ success: true, data: { sessionId } });
  } catch (error: any) {
    res.status(400).json({ success: false, error: { code: 'SESSION_CREATE_FAILED', message: error.message } });
  }
});

// POST /api/v1/chat/message
const SendMessageSchema = z.object({
  sessionId: z.string().min(1),
  message: z.string().min(1).max(4000),
});

router.post('/message', async (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  const parsed = SendMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.message } });
  }

  try {
    const reply = await sendMessage(parsed.data.sessionId, userId, parsed.data.message);
    res.json({ success: true, data: { reply } });
  } catch (error: any) {
    if (error.message === 'Session not found') {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: error.message } });
    }
    console.error('Chat message error:', error);
    const { code, message } = parseAnthropicError(error);
    res.status(500).json({ success: false, error: { code, message } });
  }
});

// GET /api/v1/chat/session/:sessionId/messages
router.get('/session/:sessionId/messages', async (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  try {
    const messages = await getMessages(req.params.sessionId, userId);
    res.json({ success: true, data: { messages } });
  } catch (error: any) {
    if (error.message === 'Session not found') {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: error.message } });
    }
    res.status(500).json({ success: false, error: { code: 'INTERNAL_ERROR', message: error.message } });
  }
});

// GET /api/v1/chat/sessions — list all threads for user
router.get('/sessions', (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  const db = getDb();

  const sessions = (db.prepare(`
    SELECT
      s.id,
      s.title,
      s.entry_id,
      s.started_at,
      s.last_message_at,
      je.audio_duration_seconds,
      je.input_type,
      (SELECT content FROM chat_messages WHERE session_id = s.id AND role = 'user'
       ORDER BY created_at DESC LIMIT 1) AS last_user_msg,
      (SELECT content FROM chat_messages WHERE session_id = s.id AND role = 'assistant'
       ORDER BY created_at DESC LIMIT 1) AS last_assistant_msg
    FROM chat_sessions s
    LEFT JOIN journal_entries je ON je.id = s.entry_id
    WHERE s.user_id = ?
    ORDER BY COALESCE(s.last_message_at, s.started_at) DESC
  `).all(userId) as any[]).map(row => {
    const today = new Date().toDateString();
    const lastAt = row.last_message_at || row.started_at;
    return {
      id: row.id,
      title: row.title || 'Conversation',
      entryId: row.entry_id ?? null,
      startedAt: row.started_at,
      lastMessageAt: lastAt,
      isLive: new Date(lastAt).toDateString() === today,
      isVoice: row.input_type === 'voice' && !!row.entry_id,
      audioDurationSeconds: row.audio_duration_seconds ?? null,
      lastUserMessage: row.last_user_msg ?? null,
      lastAssistantMessage: row.last_assistant_msg ?? null,
    };
  });

  res.json({ success: true, data: { sessions } });
});

// GET /api/v1/chat/session/:sessionId — session metadata + messages
router.get('/session/:sessionId', async (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  try {
    const db = getDb();

    const session = db.prepare(
      'SELECT s.*, je.audio_duration_seconds, je.input_type FROM chat_sessions s LEFT JOIN journal_entries je ON je.id = s.entry_id WHERE s.id = ? AND s.user_id = ?'
    ).get(req.params.sessionId, userId) as any;

    if (!session) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Session not found' } });
    }

    const messages = await getMessages(req.params.sessionId, userId);

    res.json({
      success: true,
      data: {
        session: {
          id: session.id,
          title: session.title || 'Conversation',
          entryId: session.entry_id ?? null,
          startedAt: session.started_at,
          lastMessageAt: session.last_message_at ?? session.started_at,
          isVoice: session.input_type === 'voice' && !!session.entry_id,
          audioDurationSeconds: session.audio_duration_seconds ?? null,
        },
        messages,
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: { code: 'INTERNAL_ERROR', message: error.message } });
  }
});

export default router;
