import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../../db/connection';
import anthropicClient, { MODEL, MOCK_AI } from './client';
import { buildChatProcessorSystem } from '../../prompts/system/chatProcessor';

interface StartSessionOptions {
  userId: string;
  entryId?: string | null;
}

export async function startSession({ userId, entryId = null }: StartSessionOptions): Promise<string> {
  const db = getDb();

  const user = db.prepare('SELECT id FROM users WHERE id = ?').get(userId);
  if (!user) throw new Error('User not found');

  if (entryId) {
    const entry = db.prepare('SELECT id FROM journal_entries WHERE id = ? AND user_id = ?').get(entryId, userId);
    if (!entry) throw new Error('Entry not found');
  }

  const sessionId = uuidv4();
  const now = new Date().toISOString();

  db.prepare(`INSERT INTO chat_sessions (id, user_id, entry_id, started_at, status)
    VALUES (?, ?, ?, ?, 'active')`
  ).run(sessionId, userId, entryId ?? null, now);

  return sessionId;
}

export async function sendMessage(
  sessionId: string,
  userId: string,
  userMessage: string,
): Promise<string> {
  const db = getDb();

  const session = db.prepare('SELECT * FROM chat_sessions WHERE id = ? AND user_id = ?')
    .get(sessionId, userId) as any;
  if (!session) throw new Error('Session not found');

  const profileRow = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  if (!profileRow) throw new Error('User not found');

  const profile = {
    currentRole: profileRow.current_role,
    currentCompany: profileRow.current_company,
    industry: profileRow.industry,
    careerStage: profileRow.career_stage,
    shortTermGoal: profileRow.short_term_goal,
    longTermGoal: profileRow.long_term_goal,
    currentFocusArea: profileRow.current_focus_area,
    coachingStyle: profileRow.coaching_style,
    accountabilityLevel: profileRow.accountability_level,
  };

  const activeGoals = (db.prepare(
    "SELECT id, title, progress_percent FROM goals WHERE user_id = ? AND status = 'active'"
  ).all(userId) as any[]).map(g => ({
    id: g.id,
    title: g.title,
    progressPercent: g.progress_percent,
  }));

  const recentThemes = (db.prepare(
    'SELECT label, count FROM career_themes WHERE user_id = ? ORDER BY count DESC LIMIT 10'
  ).all(userId) as any[]).map(t => ({ label: t.label, count: t.count }));

  let entryAnalysis: any = null;
  if (session.entry_id) {
    const entryRow = db.prepare('SELECT analysis_id FROM journal_entries WHERE id = ?')
      .get(session.entry_id) as any;
    if (entryRow?.analysis_id) {
      const analysisRow = db.prepare('SELECT * FROM entry_analyses WHERE id = ?')
        .get(entryRow.analysis_id) as any;
      if (analysisRow) {
        entryAnalysis = {
          summary: analysisRow.summary,
          wins: JSON.parse(analysisRow.wins || '[]'),
          challenges: JSON.parse(analysisRow.challenges || '[]'),
          coachNote: analysisRow.coach_note,
          actionItems: JSON.parse(analysisRow.action_items || '[]'),
        };
      }
    }
  }

  const priorMessages = (db.prepare(
    'SELECT role, content FROM chat_messages WHERE session_id = ? ORDER BY created_at ASC'
  ).all(sessionId) as any[]).map(m => ({ role: m.role as 'user' | 'assistant', content: m.content }));

  const system = buildChatProcessorSystem(profile as any, activeGoals, recentThemes, entryAnalysis);

  // Capture user message timestamp BEFORE the API call
  const userMsgTime = new Date().toISOString();

  let assistantReply: string;
  if (MOCK_AI) {
    assistantReply = '[Mock mode] Real coaching is paused — add Anthropic API credits at console.anthropic.com to activate.';
  } else {
    const response = await anthropicClient.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system,
      messages: [
        ...priorMessages,
        { role: 'user', content: userMessage },
      ],
    });
    const content = response.content[0];
    if (content.type !== 'text') throw new Error('Unexpected response type from Claude');
    assistantReply = content.text;
  }

  // Capture assistant reply timestamp AFTER the call returns (naturally later)
  const assistantMsgTime = new Date().toISOString();

  const insertMsg = db.prepare(`INSERT INTO chat_messages (id, session_id, role, content, created_at)
    VALUES (?, ?, ?, ?, ?)`);

  insertMsg.run(uuidv4(), sessionId, 'user', userMessage, userMsgTime);
  insertMsg.run(uuidv4(), sessionId, 'assistant', assistantReply, assistantMsgTime);

  return assistantReply;
}

export async function getMessages(sessionId: string, userId: string) {
  const db = getDb();

  const session = db.prepare('SELECT * FROM chat_sessions WHERE id = ? AND user_id = ?')
    .get(sessionId, userId) as any;
  if (!session) throw new Error('Session not found');

  return db.prepare(
    'SELECT id, role, content, created_at FROM chat_messages WHERE session_id = ? ORDER BY created_at ASC'
  ).all(sessionId);
}
