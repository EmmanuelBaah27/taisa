import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db/connection';
import { analyzeEntry } from '../services/claude/journalAgent';
import { startSession } from '../services/claude/chatAgent';
import { parseAnalysisRow } from './entries';
import { parseAnthropicError } from '../services/claude/client';
import { logRequestError } from '../middleware/requestContext';

const router = Router();

function generateTitle(transcript: string): string {
  const words = transcript.trim().split(/\s+/).slice(0, 6).join(' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

// POST /api/v1/analyze/:entryId
router.post('/:entryId', async (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) {
    return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });
  }

  const db = getDb();
  const entry = db.prepare('SELECT * FROM journal_entries WHERE id = ? AND user_id = ?')
    .get(req.params.entryId, userId) as any;
  if (!entry) {
    return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Entry not found' } });
  }

  db.prepare("UPDATE journal_entries SET status = 'processing', updated_at = ? WHERE id = ?")
    .run(new Date().toISOString(), req.params.entryId);

  try {
    const analysis = await analyzeEntry(req.params.entryId, userId);

    // Bridge: create a chat_session + seed messages so the entry becomes a thread
    const sessionId = await startSession({ userId, entryId: req.params.entryId });
    const transcript = entry.edited_transcript || entry.raw_transcript || '';
    const title = generateTitle(transcript);
    const now = new Date().toISOString();

    const insertMsg = db.prepare(
      'INSERT INTO chat_messages (id, session_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)'
    );
    insertMsg.run(uuidv4(), sessionId, 'user', transcript, now);
    insertMsg.run(uuidv4(), sessionId, 'assistant', analysis.coachNote, now);

    db.prepare('UPDATE chat_sessions SET title = ?, last_message_at = ? WHERE id = ?')
      .run(title, now, sessionId);

    res.json({ success: true, data: { ...analysis, sessionId } });
  } catch (error: any) {
    db.prepare("UPDATE journal_entries SET status = 'error', updated_at = ? WHERE id = ?")
      .run(new Date().toISOString(), req.params.entryId);
    const { code } = parseAnthropicError(error);
    logRequestError(req, code, error);
    res.status(500).json({
      success: false,
      error: { code, message: 'Unable to analyze entry' },
    });
  }
});

// GET /api/v1/analyze/:entryId
router.get('/:entryId', (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) {
    return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });
  }

  const db = getDb();
  const entry = db.prepare('SELECT * FROM journal_entries WHERE id = ? AND user_id = ?')
    .get(req.params.entryId, userId) as any;
  if (!entry || !entry.analysis_id) {
    return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'No analysis found' } });
  }

  const row = db.prepare('SELECT * FROM entry_analyses WHERE id = ?').get(entry.analysis_id) as any;
  res.json({ success: true, data: parseAnalysisRow(row) });
});

export default router;
