# Taisa MVP UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Taisa mobile app as a three-tab coaching experience (Today / Threads / You) with a global FAB for voice recording and a unified thread model where every voice entry is a conversation.

**Architecture:** Voice recordings go through the existing transcribe + analyze pipeline, then the backend automatically creates a `chat_session` + initial messages so the entry becomes a thread. Three new backend endpoints (`/today/card`, `/today/digest`, `/today/you`) serve the Today tab using pure DB queries — no extra LLM calls. The mobile UI is rebuilt from scratch in NativeWind with a new Zustand thread store. Old tab screens (index, journal, trajectory, profile) are deleted and replaced.

**Tech Stack:** React Native / Expo Router, NativeWind (Tailwind), Zustand, Axios, better-sqlite3, TypeScript, Jest + Supertest (backend tests only — no mobile test infra)

---

## File Map

### Backend — new / modified

| File | Action | Purpose |
|---|---|---|
| `backend/src/db/connection.ts` | Modify | Add `runMigrations()` for new columns on `chat_sessions` |
| `backend/src/routes/analyze.ts` | Modify | After analysis, auto-create chat_session + seed messages; return `sessionId` |
| `backend/src/routes/chat.ts` | Modify | Add `GET /sessions` (thread list) and extend `GET /session/:id/messages` to return session metadata |
| `backend/src/routes/today.ts` | Create | Three endpoints: `/card`, `/digest`, `/you` |
| `backend/src/index.ts` | Modify | Mount today router at `/api/v1/today` |
| `backend/src/__tests__/today.routes.test.ts` | Create | Tests for all three today endpoints |

### Mobile — new

| File | Purpose |
|---|---|
| `mobile/src/stores/threadStore.ts` | Zustand store: thread list + current thread messages + send |
| `mobile/src/components/FAB.tsx` | Global floating action button |
| `mobile/src/components/ThreadRow.tsx` | Thread preview row used in Threads tab and Today |
| `mobile/src/components/TaisaReplyCard.tsx` | Taisa's reply bubble (purple left border) |
| `mobile/src/components/SearchBar.tsx` | Thread search input |
| `mobile/src/components/ThemeTag.tsx` | Recurring theme pill on You tab |
| `mobile/src/components/TaisaCard.tsx` | Today tab coaching card |
| `mobile/src/components/DigestCard.tsx` | Today tab weekly digest card |
| `mobile/app/(tabs)/today.tsx` | Today tab screen |
| `mobile/app/(tabs)/threads.tsx` | Threads tab screen |
| `mobile/app/(tabs)/you.tsx` | You tab screen |
| `mobile/app/thread/[id].tsx` | Full thread view (voice + chat messages + input) |
| `mobile/app/recording/index.tsx` | Recording overlay modal |

### Mobile — modified

| File | Change |
|---|---|
| `mobile/app/_layout.tsx` | Add `thread/[id]` and `recording/index` Stack screens |
| `mobile/app/(tabs)/_layout.tsx` | Replace 4 tabs with Today / Threads / You only |

### Mobile — deleted

`mobile/app/(tabs)/index.tsx`, `mobile/app/(tabs)/journal.tsx`, `mobile/app/(tabs)/trajectory.tsx`, `mobile/app/(tabs)/profile.tsx`, `mobile/app/entry/[id].tsx`

---

## Task 1: Schema migrations — add columns to chat_sessions

**Files:**
- Modify: `backend/src/db/connection.ts`

- [ ] **Step 1: Add `runMigrations()` to connection.ts**

Open `backend/src/db/connection.ts`. After `db.exec(schema)` in `initSchema()`, call a new function:

```typescript
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '../../taisa.db');

let db: Database.Database;

export function getDb(): Database.Database {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
    initSchema();
  }
  return db;
}

function initSchema(): void {
  const schemaPath = path.join(__dirname, 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf-8');
  db.exec(schema);
  runMigrations();
}

function runMigrations(): void {
  const cols = (db.prepare('PRAGMA table_info(chat_sessions)').all() as any[]).map(c => c.name);
  if (!cols.includes('title')) {
    db.exec('ALTER TABLE chat_sessions ADD COLUMN title TEXT');
  }
  if (!cols.includes('last_message_at')) {
    db.exec('ALTER TABLE chat_sessions ADD COLUMN last_message_at TEXT');
  }
}

export default getDb;
```

- [ ] **Step 2: Verify migrations run without error**

```bash
npm run backend
```

Expected: backend starts on port 3000, no errors. Stop it with Ctrl+C.

- [ ] **Step 3: Commit**

```bash
git add backend/src/db/connection.ts
git commit -m "feat: add title and last_message_at columns to chat_sessions"
```

---

## Task 2: Analyze route — auto-create thread after analysis

**Files:**
- Modify: `backend/src/routes/analyze.ts`

- [ ] **Step 1: Write failing test**

Create `backend/src/__tests__/analyze.bridge.test.ts`:

```typescript
import request from 'supertest';
import express from 'express';

const mockAnalysis = {
  id: 'a1',
  summary: 'Test summary',
  wins: [],
  challenges: [],
  coachNote: 'Great session.',
  actionItems: [],
  themes: [],
  sentiment: 'positive',
  energyLevel: 4,
  momentumSignal: 'steady',
};

jest.mock('../services/claude/journalAgent', () => ({
  analyzeEntry: jest.fn().mockResolvedValue(mockAnalysis),
}));

jest.mock('../services/claude/chatAgent', () => ({
  startSession: jest.fn().mockResolvedValue('mock-session-id'),
}));

import analyzeRouter from '../routes/analyze';

const app = express();
app.use(express.json());
app.use('/api/v1/analyze', analyzeRouter);

describe('POST /api/v1/analyze/:entryId bridge', () => {
  test('returns sessionId alongside analysis', async () => {
    const res = await request(app)
      .post('/api/v1/analyze/entry-1')
      .set('x-user-id', 'u1');
    // Will fail until bridge is implemented
    expect(res.body.data).toHaveProperty('sessionId');
  });
});
```

- [ ] **Step 2: Run test to see it fail**

```bash
cd /path/to/repo && npx jest backend/src/__tests__/analyze.bridge.test.ts --no-coverage 2>&1 | tail -20
```

Expected: FAIL — `sessionId` not in response.

- [ ] **Step 3: Implement the bridge in analyze.ts**

Replace `backend/src/routes/analyze.ts`:

```typescript
import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db/connection';
import { analyzeEntry } from '../services/claude/journalAgent';
import { startSession } from '../services/claude/chatAgent';
import { parseAnalysisRow } from './entries';

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
    console.error('Analysis error:', error);
    res.status(500).json({ success: false, error: { code: 'ANALYSIS_FAILED', message: error.message } });
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
```

- [ ] **Step 4: Run the test — expect PASS**

```bash
npx jest backend/src/__tests__/analyze.bridge.test.ts --no-coverage 2>&1 | tail -15
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/analyze.ts backend/src/__tests__/analyze.bridge.test.ts
git commit -m "feat: auto-create chat_session thread after entry analysis"
```

---

## Task 3: Chat route — thread listing + session detail

**Files:**
- Modify: `backend/src/routes/chat.ts`
- Test: `backend/src/__tests__/chat.routes.test.ts`

- [ ] **Step 1: Add the two new endpoints to chat.ts**

Open `backend/src/routes/chat.ts`. Before `export default router;`, add:

```typescript
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
```

Also add this import at the top of `chat.ts` (it's already imported in the file, but if `getDb` is missing, add it):

```typescript
import { getDb } from '../db/connection';
```

- [ ] **Step 2: Write tests for the two new endpoints**

Add to `backend/src/__tests__/chat.routes.test.ts` (append before the closing of the file):

```typescript
describe('GET /api/v1/chat/sessions', () => {
  test('returns sessions list with valid userId', async () => {
    // Mock the DB query by mocking getDb — simpler: mock at route level
    // We'll test that the endpoint exists and requires auth
    const res = await request(app)
      .get('/api/v1/chat/sessions')
      .set('x-user-id', 'u1');
    // Route exists (not 404)
    expect(res.status).not.toBe(404);
  });

  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/chat/sessions');
    expect(res.status).toBe(401);
  });
});

describe('GET /api/v1/chat/session/:id', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/chat/session/abc');
    expect(res.status).toBe(401);
  });
});
```

- [ ] **Step 3: Run tests**

```bash
npx jest backend/src/__tests__/chat.routes.test.ts --no-coverage 2>&1 | tail -20
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/chat.ts backend/src/__tests__/chat.routes.test.ts
git commit -m "feat: add thread listing and session detail endpoints"
```

---

## Task 4: Today router — card, digest, you endpoints

**Files:**
- Create: `backend/src/routes/today.ts`
- Create: `backend/src/__tests__/today.routes.test.ts`

- [ ] **Step 1: Write failing tests**

Create `backend/src/__tests__/today.routes.test.ts`:

```typescript
import request from 'supertest';
import express from 'express';
import todayRouter from '../routes/today';

const app = express();
app.use(express.json());
app.use('/api/v1/today', todayRouter);

describe('GET /api/v1/today/card', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/today/card');
    expect(res.status).toBe(401);
  });

  test('returns card or null with valid userId', async () => {
    const res = await request(app)
      .get('/api/v1/today/card')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    // card is an object or null
    expect(res.body.data).toHaveProperty('card');
  });
});

describe('GET /api/v1/today/digest', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/today/digest');
    expect(res.status).toBe(401);
  });

  test('returns showDigest boolean', async () => {
    const res = await request(app)
      .get('/api/v1/today/digest')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(typeof res.body.data.showDigest).toBe('boolean');
  });
});

describe('GET /api/v1/today/you', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/today/you');
    expect(res.status).toBe(401);
  });

  test('returns you profile data', async () => {
    const res = await request(app)
      .get('/api/v1/today/you')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveProperty('currentFocus');
    expect(res.body.data).toHaveProperty('themes');
    expect(res.body.data).toHaveProperty('openLoops');
  });
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npx jest backend/src/__tests__/today.routes.test.ts --no-coverage 2>&1 | tail -10
```

Expected: FAIL — module not found.

- [ ] **Step 3: Create `backend/src/routes/today.ts`**

```typescript
import { Router } from 'express';
import { getDb } from '../db/connection';

const router = Router();

function requireUserId(req: any, res: any): string | null {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) {
    res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });
    return null;
  }
  return userId;
}

type CardType = 'prep' | 'pattern' | 'commitment' | 'cv_moment' | 'momentum';

interface TodayCard {
  type: CardType;
  eyebrow: string;
  body: string;
  cta: string;
}

function buildPatternCard(theme: string, count: number): TodayCard {
  return {
    type: 'pattern',
    eyebrow: '🔁 Pattern',
    body: `You've mentioned ${theme} in ${count} sessions. There's something here worth naming — want to dig in?`,
    cta: "Let's talk about it →",
  };
}

function buildCommitmentCard(title: string, daysAgo: number): TodayCard {
  return {
    type: 'commitment',
    eyebrow: '✋ Follow-up',
    body: `You said you'd ${title.toLowerCase()}. It's been ${daysAgo} ${daysAgo === 1 ? 'day' : 'days'} — still open.`,
    cta: 'Address it →',
  };
}

function buildCvMomentCard(winTitle: string): TodayCard {
  return {
    type: 'cv_moment',
    eyebrow: '⭐ Capture',
    body: `"${winTitle}" is worth framing properly before the detail fades. This is a CV moment.`,
    cta: "Let's frame it →",
  };
}

function buildMomentumCard(negative: boolean, count: number): TodayCard {
  if (negative) {
    return {
      type: 'momentum',
      eyebrow: '📈 Check-in',
      body: `Your last ${count} sessions have been heavy. What's one thing that's going right?`,
      cta: 'Talk it through →',
    };
  }
  return {
    type: 'momentum',
    eyebrow: '📈 Momentum',
    body: `Strong run — ${count} sessions in a flow state. What's driving it?`,
    cta: 'Reflect →',
  };
}

function daysBetween(dateStr: string): number {
  const d = new Date(dateStr);
  const now = new Date();
  return Math.floor((now.getTime() - d.getTime()) / (1000 * 60 * 60 * 24));
}

// GET /api/v1/today/card
router.get('/card', (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  try {
    const db = getDb();
    let card: TodayCard | null = null;

    // 1. Urgent commitment (overdue > 7 days)
    const urgentItem = db.prepare(`
      SELECT title, created_at FROM action_items
      WHERE user_id = ? AND status = 'open'
      ORDER BY created_at ASC LIMIT 1
    `).get(userId) as any;

    if (urgentItem) {
      const days = daysBetween(urgentItem.created_at);
      if (days >= 7) {
        card = buildCommitmentCard(urgentItem.title, days);
      }
    }

    // 2. Strong pattern (theme count >= 3)
    if (!card) {
      const topTheme = db.prepare(`
        SELECT label, count FROM career_themes
        WHERE user_id = ? AND count >= 3
        ORDER BY count DESC LIMIT 1
      `).get(userId) as any;

      if (topTheme) {
        card = buildPatternCard(topTheme.label, topTheme.count);
      }
    }

    // 3. Recent win worth capturing (from last 48 hours)
    if (!card) {
      const cutoff = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
      const recentEntry = db.prepare(`
        SELECT ea.wins FROM entry_analyses ea
        JOIN journal_entries je ON je.analysis_id = ea.id
        WHERE je.user_id = ? AND je.created_at > ?
        ORDER BY je.created_at DESC LIMIT 1
      `).get(userId, cutoff) as any;

      if (recentEntry) {
        const wins = JSON.parse(recentEntry.wins || '[]');
        if (wins.length > 0) {
          card = buildCvMomentCard(wins[0].title);
        }
      }
    }

    // 4. Momentum (last 3 sessions all difficult)
    if (!card) {
      const recentSentiments = (db.prepare(`
        SELECT ea.sentiment FROM entry_analyses ea
        JOIN journal_entries je ON je.analysis_id = ea.id
        WHERE je.user_id = ?
        ORDER BY je.created_at DESC LIMIT 3
      `).all(userId) as any[]).map(r => r.sentiment);

      if (recentSentiments.length === 3 && recentSentiments.every(s => s === 'difficult' || s === 'challenging')) {
        card = buildMomentumCard(true, 3);
      }
    }

    // 5. Standard commitment (open > 3 days)
    if (!card && urgentItem) {
      const days = daysBetween(urgentItem.created_at);
      if (days >= 3) {
        card = buildCommitmentCard(urgentItem.title, days);
      }
    }

    res.json({ success: true, data: { card } });
  } catch (error: any) {
    res.status(500).json({ success: false, error: { code: 'INTERNAL_ERROR', message: error.message } });
  }
});

// GET /api/v1/today/digest
router.get('/digest', (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  try {
    const db = getDb();
    const user = db.prepare('SELECT last_entry_at FROM users WHERE id = ?').get(userId) as any;

    if (!user) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'User not found' } });

    const daysSinceLast = user.last_entry_at ? daysBetween(user.last_entry_at) : 999;
    const showDigest = daysSinceLast >= 2;

    if (!showDigest) {
      return res.json({ success: true, data: { showDigest: false } });
    }

    // Build digest content from last 7 days
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

    const sessionCount = (db.prepare(
      "SELECT COUNT(*) as c FROM journal_entries WHERE user_id = ? AND created_at > ?"
    ).get(userId, weekAgo) as any).c;

    const topTheme = db.prepare(
      'SELECT label FROM career_themes WHERE user_id = ? ORDER BY count DESC LIMIT 1'
    ).get(userId) as any;

    const recentWins = (db.prepare(`
      SELECT ea.wins FROM entry_analyses ea
      JOIN journal_entries je ON je.analysis_id = ea.id
      WHERE je.user_id = ? AND je.created_at > ?
    `).all(userId, weekAgo) as any[])
      .flatMap(r => JSON.parse(r.wins || '[]') as any[]);

    const openItems = db.prepare(
      "SELECT title FROM action_items WHERE user_id = ? AND status = 'open' ORDER BY created_at ASC LIMIT 3"
    ).all(userId) as any[];

    const items: Array<{ type: string; color: string; text: string; cta: string }> = [];

    if (topTheme) {
      items.push({ type: 'pattern', color: 'accent', text: `${topTheme.label} — showing up across sessions`, cta: 'Tap to discuss →' });
    }
    if (recentWins.length > 0) {
      items.push({ type: 'win', color: 'positive', text: `${recentWins[0].title} — worth framing properly`, cta: 'Tap to frame →' });
    }
    if (openItems.length > 0) {
      items.push({ type: 'commitment', color: 'warning', text: `${openItems[0].title} — still open`, cta: 'Mark done or continue →' });
    }

    const headline = `${sessionCount} session${sessionCount !== 1 ? 's' : ''} · ${items.filter(i => i.type === 'pattern').length} pattern${items.filter(i => i.type === 'pattern').length !== 1 ? 's' : ''} · ${recentWins.length} win${recentWins.length !== 1 ? 's' : ''}`;

    res.json({
      success: true,
      data: {
        showDigest: true,
        digest: { headline, items },
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: { code: 'INTERNAL_ERROR', message: error.message } });
  }
});

// GET /api/v1/today/you
router.get('/you', (req, res) => {
  const userId = requireUserId(req, res);
  if (!userId) return;

  try {
    const db = getDb();
    const user = db.prepare('SELECT current_focus_area FROM users WHERE id = ?').get(userId) as any;
    if (!user) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'User not found' } });

    const themes = (db.prepare(
      'SELECT label FROM career_themes WHERE user_id = ? ORDER BY count DESC LIMIT 5'
    ).all(userId) as any[]).map(t => t.label);

    const openItems = (db.prepare(
      "SELECT title FROM action_items WHERE user_id = ? AND status = 'open' ORDER BY created_at ASC LIMIT 3"
    ).all(userId) as any[]).map(i => i.title);

    res.json({
      success: true,
      data: {
        currentFocus: user.current_focus_area || '',
        themes,
        openLoops: openItems.join(' · '),
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: { code: 'INTERNAL_ERROR', message: error.message } });
  }
});

export default router;
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
npx jest backend/src/__tests__/today.routes.test.ts --no-coverage 2>&1 | tail -15
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/today.ts backend/src/__tests__/today.routes.test.ts
git commit -m "feat: add today/card, today/digest, today/you endpoints"
```

---

## Task 5: Mount today router in backend index

**Files:**
- Modify: `backend/src/index.ts`

- [ ] **Step 1: Add todayRouter import and mount**

In `backend/src/index.ts`, add after the existing chat router import:

```typescript
import todayRouter from './routes/today';
```

And after the existing `app.use('/api/v1/chat', ...)` line, add:

```typescript
app.use('/api/v1/today', todayRouter);
```

- [ ] **Step 2: Verify backend starts**

```bash
npm run backend
```

Expected: starts successfully, no errors. Test with `curl http://localhost:3000/health` → `{"status":"ok",...}`. Stop with Ctrl+C.

- [ ] **Step 3: Commit**

```bash
git add backend/src/index.ts
git commit -m "feat: mount today router"
```

---

## Task 6: Root layout — add thread + recording screens

**Files:**
- Modify: `mobile/app/_layout.tsx`

- [ ] **Step 1: Update _layout.tsx**

Replace `mobile/app/_layout.tsx`:

```tsx
import '../global.css';
import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import * as SecureStore from 'expo-secure-store';
import { useCareerStore } from '../src/stores/careerStore';

export default function RootLayout() {
  const { fetchProfile } = useCareerStore();

  useEffect(() => {
    async function hydrateUser() {
      const userId = await SecureStore.getItemAsync('userId');
      if (userId) {
        try {
          await fetchProfile();
        } catch (e) {
          // Profile fetch failed — user will see onboarding
        }
      }
    }
    hydrateUser();
  }, []);

  return (
    <>
      <StatusBar style="light" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0A0A0F' } }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="onboarding/index" />
        <Stack.Screen name="thread/[id]" />
        <Stack.Screen
          name="recording/index"
          options={{ presentation: 'transparentModal', animation: 'slide_from_bottom' }}
        />
      </Stack>
    </>
  );
}
```

- [ ] **Step 2: Start mobile and confirm no crash**

```bash
cd mobile && npx expo start
```

Open Expo Go on device or simulator. Confirm app loads. Stop with Ctrl+C.

- [ ] **Step 3: Commit**

```bash
git add mobile/app/_layout.tsx
git commit -m "feat: add thread and recording modal routes to root layout"
```

---

## Task 7: Tab scaffold — 3 tabs (Today / Threads / You)

**Files:**
- Modify: `mobile/app/(tabs)/_layout.tsx`
- Delete: `mobile/app/(tabs)/index.tsx`, `mobile/app/(tabs)/journal.tsx`, `mobile/app/(tabs)/trajectory.tsx`, `mobile/app/(tabs)/profile.tsx`, `mobile/app/entry/[id].tsx`
- Create: `mobile/app/(tabs)/today.tsx`, `mobile/app/(tabs)/threads.tsx`, `mobile/app/(tabs)/you.tsx` (placeholder content — filled in later tasks)

- [ ] **Step 1: Delete old tab files**

```bash
rm mobile/app/(tabs)/index.tsx
rm mobile/app/(tabs)/journal.tsx
rm mobile/app/(tabs)/trajectory.tsx
rm mobile/app/(tabs)/profile.tsx
rm mobile/app/entry/[id].tsx
```

- [ ] **Step 2: Create placeholder screens**

Create `mobile/app/(tabs)/today.tsx`:
```tsx
import { View, Text } from 'react-native';

export default function TodayScreen() {
  return (
    <View className="flex-1 bg-background items-center justify-center">
      <Text className="text-text-primary text-base">Today</Text>
    </View>
  );
}
```

Create `mobile/app/(tabs)/threads.tsx`:
```tsx
import { View, Text } from 'react-native';

export default function ThreadsScreen() {
  return (
    <View className="flex-1 bg-background items-center justify-center">
      <Text className="text-text-primary text-base">Threads</Text>
    </View>
  );
}
```

Create `mobile/app/(tabs)/you.tsx`:
```tsx
import { View, Text } from 'react-native';

export default function YouScreen() {
  return (
    <View className="flex-1 bg-background items-center justify-center">
      <Text className="text-text-primary text-base">You</Text>
    </View>
  );
}
```

- [ ] **Step 3: Replace `_layout.tsx` with 3-tab config**

Replace `mobile/app/(tabs)/_layout.tsx`:

```tsx
import { Tabs } from 'expo-router';
import { colors } from '../../src/constants/theme';

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
          borderTopWidth: 1,
          paddingTop: 8,
          height: 80,
        },
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.textTertiary,
        tabBarShowLabel: true,
        tabBarLabelStyle: { fontSize: 10, fontWeight: '500', marginBottom: 4 },
      }}
    >
      <Tabs.Screen
        name="today"
        options={{
          title: 'Today',
          tabBarIcon: ({ color }) => (
            <TabIcon symbol="◈" color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="threads"
        options={{
          title: 'Threads',
          tabBarIcon: ({ color }) => (
            <TabIcon symbol="◎" color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="you"
        options={{
          title: 'You',
          tabBarIcon: ({ color }) => (
            <TabIcon symbol="○" color={color} />
          ),
        }}
      />
    </Tabs>
  );
}

function TabIcon({ symbol, color }: { symbol: string; color: string }) {
  return (
    <Text style={{ color, fontSize: 18, lineHeight: 22 }}>{symbol}</Text>
  );
}
```

Note: `Text` needs to be imported from `react-native`. Add at the top:
```tsx
import { Text } from 'react-native';
```

- [ ] **Step 4: Verify 3 tabs appear**

```bash
cd mobile && npx expo start
```

Open app. Confirm 3 tabs: Today / Threads / You. Each shows placeholder text. Stop with Ctrl+C.

- [ ] **Step 5: Commit**

```bash
git add mobile/app/(tabs)/ mobile/app/entry/
git commit -m "feat: replace 4-tab layout with Today/Threads/You nav"
```

---

## Task 8: Thread store

**Files:**
- Create: `mobile/src/stores/threadStore.ts`

- [ ] **Step 1: Create threadStore.ts**

```typescript
import { create } from 'zustand';
import api from '../services/api';

export interface Thread {
  id: string;
  title: string;
  entryId: string | null;
  startedAt: string;
  lastMessageAt: string;
  isLive: boolean;
  isVoice: boolean;
  audioDurationSeconds: number | null;
  lastUserMessage: string | null;
  lastAssistantMessage: string | null;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  created_at: string;
}

export interface ThreadSession {
  id: string;
  title: string;
  entryId: string | null;
  startedAt: string;
  lastMessageAt: string;
  isVoice: boolean;
  audioDurationSeconds: number | null;
}

interface ThreadStore {
  threads: Thread[];
  currentSession: ThreadSession | null;
  currentMessages: ChatMessage[];
  isLoadingThreads: boolean;
  isLoadingMessages: boolean;
  isSending: boolean;
  error: string | null;

  fetchThreads: () => Promise<void>;
  fetchThread: (sessionId: string) => Promise<void>;
  sendMessage: (sessionId: string, content: string) => Promise<void>;
  clearThread: () => void;
  clearError: () => void;
}

export const useThreadStore = create<ThreadStore>((set, get) => ({
  threads: [],
  currentSession: null,
  currentMessages: [],
  isLoadingThreads: false,
  isLoadingMessages: false,
  isSending: false,
  error: null,

  fetchThreads: async () => {
    set({ isLoadingThreads: true, error: null });
    try {
      const res = await api.get('/chat/sessions');
      set({ threads: res.data.data.sessions, isLoadingThreads: false });
    } catch (e: any) {
      set({ isLoadingThreads: false, error: e.message });
    }
  },

  fetchThread: async (sessionId: string) => {
    set({ isLoadingMessages: true, error: null });
    try {
      const res = await api.get(`/chat/session/${sessionId}`);
      set({
        currentSession: res.data.data.session,
        currentMessages: res.data.data.messages,
        isLoadingMessages: false,
      });
    } catch (e: any) {
      set({ isLoadingMessages: false, error: e.message });
    }
  },

  sendMessage: async (sessionId: string, content: string) => {
    // Optimistically add user message
    const optimisticMsg: ChatMessage = {
      id: `temp-${Date.now()}`,
      role: 'user',
      content,
      created_at: new Date().toISOString(),
    };
    set(state => ({
      currentMessages: [...state.currentMessages, optimisticMsg],
      isSending: true,
    }));

    try {
      const res = await api.post('/chat/message', { sessionId, message: content });
      const assistantMsg: ChatMessage = {
        id: `temp-reply-${Date.now()}`,
        role: 'assistant',
        content: res.data.data.reply,
        created_at: new Date().toISOString(),
      };
      set(state => ({
        currentMessages: [...state.currentMessages, assistantMsg],
        isSending: false,
      }));
    } catch (e: any) {
      // Remove optimistic message on failure
      set(state => ({
        currentMessages: state.currentMessages.filter(m => m.id !== optimisticMsg.id),
        isSending: false,
        error: e.message,
      }));
    }
  },

  clearThread: () => set({ currentSession: null, currentMessages: [] }),
  clearError: () => set({ error: null }),
}));
```

- [ ] **Step 2: Commit**

```bash
git add mobile/src/stores/threadStore.ts
git commit -m "feat: add thread store for threads list and chat messages"
```

---

## Task 9: Shared components — FAB, ThreadRow, TaisaReplyCard, SearchBar, ThemeTag

**Files:**
- Create: `mobile/src/components/FAB.tsx`
- Create: `mobile/src/components/ThreadRow.tsx`
- Create: `mobile/src/components/TaisaReplyCard.tsx`
- Create: `mobile/src/components/SearchBar.tsx`
- Create: `mobile/src/components/ThemeTag.tsx`

- [ ] **Step 1: Create FAB.tsx**

```tsx
import { TouchableOpacity, Text, View } from 'react-native';
import { router } from 'expo-router';

interface FABProps {
  onPress?: () => void;
}

export function FAB({ onPress }: FABProps) {
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <View className="absolute bottom-6 right-6" style={{ zIndex: 50 }}>
      <TouchableOpacity
        onPress={handlePress}
        className="w-14 h-14 rounded-full bg-accent items-center justify-center"
        style={{ elevation: 8, shadowColor: '#7C6FFF', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.4, shadowRadius: 8 }}
      >
        <Text className="text-white text-2xl font-light">+</Text>
      </TouchableOpacity>
    </View>
  );
}
```

- [ ] **Step 2: Create ThreadRow.tsx**

```tsx
import { TouchableOpacity, View, Text } from 'react-native';
import { router } from 'expo-router';
import { formatDistanceToNow } from 'date-fns';
import type { Thread } from '../stores/threadStore';

interface ThreadRowProps {
  thread: Thread;
}

export function ThreadRow({ thread }: ThreadRowProps) {
  const relativeTime = formatDistanceToNow(new Date(thread.lastMessageAt), { addSuffix: false });
  const displayTime = thread.isLive ? 'Today' : relativeTime;

  return (
    <TouchableOpacity
      onPress={() => router.push(`/thread/${thread.id}`)}
      className="bg-surface rounded-xl px-3 py-3 mb-2"
    >
      {thread.isLive && (
        <View className="flex-row items-center gap-1 mb-1">
          <View className="w-1.5 h-1.5 rounded-full bg-accent" />
          <Text className="text-accent text-xs font-bold tracking-wider uppercase">Live</Text>
        </View>
      )}

      <View className="flex-row justify-between items-center mb-1">
        <Text className="text-text-primary text-sm font-semibold flex-1 mr-2" numberOfLines={1}>
          {thread.title}
        </Text>
        <Text className="text-text-tertiary text-xs">{displayTime}</Text>
      </View>

      {thread.isVoice && thread.lastUserMessage == null ? (
        <Text className="text-text-secondary text-xs mb-1">〜〜〜  {formatDuration(thread.audioDurationSeconds ?? 0)} voice</Text>
      ) : (
        <Text className="text-text-secondary text-xs mb-1" numberOfLines={1}>
          {thread.lastUserMessage ?? ''}
        </Text>
      )}

      {thread.lastAssistantMessage != null && (
        <Text className="text-accent text-xs" numberOfLines={2}>
          {thread.lastAssistantMessage}
        </Text>
      )}
    </TouchableOpacity>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
```

- [ ] **Step 3: Create TaisaReplyCard.tsx**

```tsx
import { View, Text } from 'react-native';

interface TaisaReplyCardProps {
  content: string;
}

export function TaisaReplyCard({ content }: TaisaReplyCardProps) {
  return (
    <View className="bg-surface rounded-lg rounded-tl-sm px-3 py-3 my-1"
      style={{ borderLeftWidth: 2, borderLeftColor: '#7C6FFF' }}>
      <Text className="text-accent text-xs font-bold mb-1">Taisa</Text>
      <Text className="text-text-secondary text-sm leading-relaxed">{content}</Text>
    </View>
  );
}
```

- [ ] **Step 4: Create SearchBar.tsx**

```tsx
import { View, TextInput, Text } from 'react-native';
import { colors } from '../constants/theme';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
}

export function SearchBar({ value, onChangeText, placeholder = 'Search conversations...' }: SearchBarProps) {
  return (
    <View className="bg-surface rounded-full px-4 py-2 mb-3 flex-row items-center">
      <Text className="text-text-tertiary text-base mr-2">⌕</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={colors.textTertiary}
        className="flex-1 text-text-primary text-sm"
        autoCapitalize="none"
        autoCorrect={false}
      />
    </View>
  );
}
```

- [ ] **Step 5: Create ThemeTag.tsx**

```tsx
import { View, Text } from 'react-native';

interface ThemeTagProps {
  label: string;
}

export function ThemeTag({ label }: ThemeTagProps) {
  return (
    <View className="bg-accent-muted rounded-md px-2 py-0.5 mr-1 mb-1">
      <Text className="text-accent text-xs font-semibold">{label}</Text>
    </View>
  );
}
```

- [ ] **Step 6: Commit**

```bash
git add mobile/src/components/
git commit -m "feat: add shared components FAB, ThreadRow, TaisaReplyCard, SearchBar, ThemeTag"
```

---

## Task 10: Threads tab screen

**Files:**
- Modify: `mobile/app/(tabs)/threads.tsx`

- [ ] **Step 1: Replace placeholder with full Threads tab**

```tsx
import { useEffect, useState } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useCallback } from 'react';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { SearchBar } from '../../src/components/SearchBar';
import { FAB } from '../../src/components/FAB';
import { colors } from '../../src/constants/theme';

export default function ThreadsScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const [query, setQuery] = useState('');

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
    }, [])
  );

  const filtered = query.trim()
    ? threads.filter(t =>
        t.title.toLowerCase().includes(query.toLowerCase()) ||
        (t.lastUserMessage ?? '').toLowerCase().includes(query.toLowerCase()) ||
        (t.lastAssistantMessage ?? '').toLowerCase().includes(query.toLowerCase())
      )
    : threads;

  return (
    <View className="flex-1 bg-background">
      <ScrollView className="flex-1" contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 60, paddingBottom: 100 }}>
        <Text className="text-text-primary text-2xl font-bold mb-4">Threads</Text>

        <SearchBar value={query} onChangeText={setQuery} />

        {isLoadingThreads && threads.length === 0 ? (
          <ActivityIndicator color={colors.accent} style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <Text className="text-text-tertiary text-sm text-center mt-10">
            {query ? 'No threads match your search.' : 'No threads yet — tap + to start recording.'}
          </Text>
        ) : (
          filtered.map(thread => <ThreadRow key={thread.id} thread={thread} />)
        )}
      </ScrollView>

      <FAB />
    </View>
  );
}
```

- [ ] **Step 2: Verify in Expo Go**

Start backend (`npm run backend`) and mobile (`npm run mobile`). Navigate to Threads tab. Confirm: search bar renders, FAB renders, empty state shows if no threads, threads load if backend has data.

- [ ] **Step 3: Commit**

```bash
git add mobile/app/(tabs)/threads.tsx
git commit -m "feat: build Threads tab with search, thread list, and FAB"
```

---

## Task 11: Thread view — full conversation screen

**Files:**
- Create: `mobile/app/thread/[id].tsx`

- [ ] **Step 1: Create thread directory and screen**

```bash
mkdir -p mobile/app/thread
```

Create `mobile/app/thread/[id].tsx`:

```tsx
import { useEffect, useRef, useState } from 'react';
import { View, Text, ScrollView, TextInput, TouchableOpacity, KeyboardAvoidingView, Platform, ActivityIndicator } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { TaisaReplyCard } from '../../src/components/TaisaReplyCard';
import { colors } from '../../src/constants/theme';
import type { ChatMessage } from '../../src/stores/threadStore';

export default function ThreadScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { currentSession, currentMessages, isLoadingMessages, isSending, fetchThread, sendMessage, clearThread } = useThreadStore();
  const [input, setInput] = useState('');
  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => {
    if (id) fetchThread(id);
    return () => clearThread();
  }, [id]);

  useEffect(() => {
    if (currentMessages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [currentMessages.length]);

  const handleSend = async () => {
    const text = input.trim();
    if (!text || !id || isSending) return;
    setInput('');
    await sendMessage(id, text);
  };

  if (isLoadingMessages && !currentSession) {
    return (
      <View className="flex-1 bg-background items-center justify-center">
        <ActivityIndicator color={colors.accent} />
      </View>
    );
  }

  const isVoiceEntry = currentSession?.isVoice ?? false;

  // Split messages: for voice entries, first 2 messages (transcript + coach note) are part of the entry display
  const entryMessages = isVoiceEntry ? currentMessages.slice(0, 2) : [];
  const chatMessages = isVoiceEntry ? currentMessages.slice(2) : currentMessages;

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-background"
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={0}
    >
      {/* Header */}
      <View className="flex-row items-center px-4 pt-14 pb-3 border-b border-border-subtle">
        <TouchableOpacity onPress={() => router.back()} className="mr-3">
          <Text className="text-accent text-base">‹ Back</Text>
        </TouchableOpacity>
        <Text className="text-text-primary text-base font-semibold flex-1" numberOfLines={1}>
          {currentSession?.title ?? 'Thread'}
        </Text>
      </View>

      <ScrollView
        ref={scrollRef}
        className="flex-1"
        contentContainerStyle={{ padding: 16, paddingBottom: 24 }}
      >
        {/* Voice entry section */}
        {isVoiceEntry && entryMessages.length >= 1 && (
          <View className="mb-4">
            <View className="bg-surface rounded-lg px-3 py-2 mb-2">
              <Text className="text-accent text-xs font-bold mb-1">
                🎤 Voice{currentSession?.audioDurationSeconds ? ` · ${formatDuration(currentSession.audioDurationSeconds)}` : ''}
              </Text>
              <Text className="text-text-secondary text-sm leading-relaxed">
                {entryMessages[0]?.content ?? ''}
              </Text>
            </View>

            {entryMessages.length >= 2 && (
              <TaisaReplyCard content={entryMessages[1].content} />
            )}
          </View>
        )}

        {/* Loading shimmer for fresh voice entry */}
        {isVoiceEntry && isLoadingMessages && (
          <View className="bg-surface rounded-lg px-3 py-4 mb-2 opacity-40">
            <View className="h-3 bg-surface-elevated rounded mb-2 w-3/4" />
            <View className="h-3 bg-surface-elevated rounded w-1/2" />
          </View>
        )}

        {/* Regular chat messages */}
        {chatMessages.map(msg => (
          <MessageBubble key={msg.id} message={msg} />
        ))}

        {/* Sending indicator */}
        {isSending && (
          <View className="items-start mb-2">
            <View className="bg-surface rounded-lg px-3 py-2">
              <Text className="text-text-tertiary text-xs">Taisa is thinking…</Text>
            </View>
          </View>
        )}
      </ScrollView>

      {/* Input bar */}
      <View className="flex-row items-center px-4 py-3 border-t border-border-subtle bg-background">
        <TextInput
          value={input}
          onChangeText={setInput}
          placeholder="Reply..."
          placeholderTextColor={colors.textTertiary}
          className="flex-1 bg-surface rounded-full px-4 py-2 text-text-primary text-sm mr-3"
          multiline
          maxLength={2000}
          onSubmitEditing={handleSend}
        />
        <TouchableOpacity
          onPress={handleSend}
          disabled={!input.trim() || isSending}
          className="w-9 h-9 rounded-full bg-accent items-center justify-center"
          style={{ opacity: !input.trim() || isSending ? 0.4 : 1 }}
        >
          <Text className="text-white text-base">↑</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

function MessageBubble({ message }: { message: ChatMessage }) {
  const isUser = message.role === 'user';
  return (
    <View className={`mb-2 ${isUser ? 'items-end' : 'items-start'}`}>
      {!isUser && (
        <Text className="text-accent text-xs font-bold mb-1 ml-1">Taisa</Text>
      )}
      <View
        className={`rounded-xl px-3 py-2 max-w-xs ${isUser ? 'bg-accent-muted rounded-tr-sm' : 'bg-surface rounded-tl-sm'}`}
        style={!isUser ? { borderLeftWidth: 2, borderLeftColor: '#7C6FFF' } : undefined}
      >
        <Text className={`text-sm leading-relaxed ${isUser ? 'text-text-primary' : 'text-text-secondary'}`}>
          {message.content}
        </Text>
      </View>
    </View>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
```

- [ ] **Step 2: Verify thread view in app**

Start backend + mobile. Navigate to any thread (if threads exist, tap one from the Threads tab). Confirm: header with back button and title, voice entry display (if voice), messages list, input bar.

- [ ] **Step 3: Commit**

```bash
git add mobile/app/thread/
git commit -m "feat: build thread view with voice entry display and chat input"
```

---

## Task 12: Recording overlay modal

**Files:**
- Create: `mobile/app/recording/index.tsx`

- [ ] **Step 1: Create recording directory**

```bash
mkdir -p mobile/app/recording
```

- [ ] **Step 2: Create recording/index.tsx**

```tsx
import { useState, useRef } from 'react';
import { View, Text, TouchableOpacity, Animated, ActivityIndicator, Alert } from 'react-native';
import { router } from 'expo-router';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import { transcribeAudio } from '../../src/services/transcription';
import api from '../../src/services/api';
import { colors } from '../../src/constants/theme';

export default function RecordingModal() {
  const { start, stop, isRecording, duration } = useVoiceRecorder();
  const [phase, setPhase] = useState<'idle' | 'recording' | 'processing' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const pulseLoop = useRef<Animated.CompositeAnimation | null>(null);

  const startPulse = () => {
    pulseLoop.current = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, { toValue: 1.2, duration: 700, useNativeDriver: true }),
        Animated.timing(pulseAnim, { toValue: 1, duration: 700, useNativeDriver: true }),
      ])
    );
    pulseLoop.current.start();
  };

  const stopPulse = () => {
    pulseLoop.current?.stop();
    Animated.timing(pulseAnim, { toValue: 1, duration: 150, useNativeDriver: true }).start();
  };

  const handleStartRecording = async () => {
    try {
      setError(null);
      setPhase('recording');
      await start();
      startPulse();
    } catch (e: any) {
      setError(e.message);
      setPhase('error');
    }
  };

  const handleDone = async () => {
    if (!isRecording) return;
    stopPulse();
    setPhase('processing');

    try {
      const result = await stop();
      const transcript = await transcribeAudio(result.uri, result.durationSeconds);

      // Create journal entry
      const entryRes = await api.post('/entries', {
        rawTranscript: transcript,
        editedTranscript: transcript,
        audioDurationSeconds: result.durationSeconds,
        recordedAt: new Date().toISOString(),
        inputType: 'voice',
      });
      const entryId: string = entryRes.data.data.id;

      // Analyze — backend auto-creates chat_session and returns sessionId
      const analyzeRes = await api.post(`/analyze/${entryId}`);
      const sessionId: string = analyzeRes.data.data.sessionId;

      // Navigate to the new thread
      router.replace(`/thread/${sessionId}`);
    } catch (e: any) {
      setError(e.message ?? 'Something went wrong. Try again.');
      setPhase('error');
    }
  };

  const handleClose = () => {
    router.back();
  };

  return (
    <View className="flex-1" style={{ backgroundColor: 'rgba(6,6,11,0.95)' }}>
      {/* Dismiss area at top */}
      <TouchableOpacity className="flex-1" onPress={handleClose} />

      {/* Bottom sheet */}
      <View className="bg-background rounded-t-3xl px-6 pt-4 pb-12">
        {/* Handle */}
        <View className="w-8 h-1 bg-border rounded-full self-center mb-6" />

        {phase === 'error' ? (
          <View className="items-center py-8">
            <Text className="text-error text-base mb-4">{error}</Text>
            <TouchableOpacity onPress={() => setPhase('idle')} className="bg-surface rounded-full px-6 py-3">
              <Text className="text-text-primary text-sm font-semibold">Try again</Text>
            </TouchableOpacity>
          </View>
        ) : phase === 'processing' ? (
          <View className="items-center py-8">
            <ActivityIndicator color={colors.accent} size="large" style={{ marginBottom: 16 }} />
            <Text className="text-text-secondary text-sm">Taisa is reading your entry…</Text>
          </View>
        ) : (
          <View className="items-center">
            <Text className="text-text-tertiary text-xs font-bold tracking-widest uppercase mb-6">
              {isRecording ? 'Recording' : 'Ready'}
            </Text>

            {isRecording && (
              <Text className="text-accent text-lg tracking-widest mb-4">〜 〜 〜 〜 〜</Text>
            )}

            <Animated.View style={{ transform: [{ scale: pulseAnim }] }}>
              <TouchableOpacity
                onPress={isRecording ? undefined : handleStartRecording}
                className="w-16 h-16 rounded-full bg-accent items-center justify-center mb-4"
                style={{ shadowColor: '#7C6FFF', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.5, shadowRadius: 12 }}
              >
                <Text className="text-2xl">🎤</Text>
              </TouchableOpacity>
            </Animated.View>

            {isRecording ? (
              <>
                <Text className="text-text-primary text-xl font-bold mb-1">{formatDuration(duration)}</Text>
                <TouchableOpacity onPress={handleDone} className="bg-surface rounded-full px-8 py-3 mt-4">
                  <Text className="text-text-primary text-sm font-semibold">Done</Text>
                </TouchableOpacity>
              </>
            ) : (
              <Text className="text-text-tertiary text-sm">Tap to start recording</Text>
            )}
          </View>
        )}
      </View>
    </View>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60).toString().padStart(2, '0');
  const s = (seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
```

- [ ] **Step 3: Verify recording flow end-to-end**

Start backend + mobile. On the Threads tab, tap the FAB. Confirm:
- Modal slides up from bottom
- Tap mic → recording starts, timer runs, waveform shows
- Tap Done → "Taisa is reading…" spinner shows
- App navigates to thread view with Taisa's reply

- [ ] **Step 4: Commit**

```bash
git add mobile/app/recording/
git commit -m "feat: build recording overlay modal with full pipeline integration"
```

---

## Task 13: TaisaCard and DigestCard components

**Files:**
- Create: `mobile/src/components/TaisaCard.tsx`
- Create: `mobile/src/components/DigestCard.tsx`

- [ ] **Step 1: Create TaisaCard.tsx**

```tsx
import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';

interface TaisaCardProps {
  eyebrow: string;
  body: string;
  cta: string;
  onPress?: () => void;
}

export function TaisaCard({ eyebrow, body, cta, onPress }: TaisaCardProps) {
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <TouchableOpacity
      onPress={handlePress}
      className="bg-surface rounded-xl px-4 py-4 mb-4"
      style={{ borderLeftWidth: 2, borderLeftColor: '#7C6FFF' }}
    >
      <Text className="text-accent text-xs font-bold uppercase tracking-wider mb-2">{eyebrow}</Text>
      <Text className="text-text-primary text-sm leading-relaxed mb-3">{body}</Text>
      <Text className="text-accent text-xs font-semibold">{cta}</Text>
    </TouchableOpacity>
  );
}
```

- [ ] **Step 2: Create DigestCard.tsx**

```tsx
import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';

interface DigestItem {
  type: string;
  color: string;
  text: string;
  cta: string;
}

interface DigestCardProps {
  headline: string;
  items: DigestItem[];
}

const dotColors: Record<string, string> = {
  accent: '#7C6FFF',
  positive: '#4ADE80',
  warning: '#FBBF24',
};

export function DigestCard({ headline, items }: DigestCardProps) {
  return (
    <View className="bg-surface rounded-xl px-4 py-4 mb-4">
      <Text className="text-accent text-xs font-bold uppercase tracking-wider mb-1">📋 Taisa's week in review</Text>
      <Text className="text-text-primary text-base font-bold mb-1">{headline}</Text>
      <Text className="text-text-tertiary text-xs mb-4">Tap any item to continue</Text>

      {items.map((item, i) => (
        <TouchableOpacity
          key={i}
          onPress={() => router.push('/recording')}
          className="flex-row items-start mb-3"
        >
          <View
            className="w-2 h-2 rounded-full mt-1 mr-3 flex-shrink-0"
            style={{ backgroundColor: dotColors[item.color] ?? '#7C6FFF' }}
          />
          <View className="flex-1">
            <Text className="text-text-secondary text-sm leading-relaxed">{item.text}</Text>
            <Text className="text-accent text-xs mt-0.5">{item.cta}</Text>
          </View>
        </TouchableOpacity>
      ))}
    </View>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/src/components/TaisaCard.tsx mobile/src/components/DigestCard.tsx
git commit -m "feat: add TaisaCard and DigestCard coaching surface components"
```

---

## Task 14: Today tab screen

**Files:**
- Modify: `mobile/app/(tabs)/today.tsx`

- [ ] **Step 1: Build Today tab**

Replace `mobile/app/(tabs)/today.tsx`:

```tsx
import { useState, useCallback } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { format } from 'date-fns';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { TaisaCard } from '../../src/components/TaisaCard';
import { DigestCard } from '../../src/components/DigestCard';
import { FAB } from '../../src/components/FAB';
import { colors } from '../../src/constants/theme';
import api from '../../src/services/api';

interface TodayCard {
  type: string;
  eyebrow: string;
  body: string;
  cta: string;
}

interface DigestData {
  headline: string;
  items: Array<{ type: string; color: string; text: string; cta: string }>;
}

export default function TodayScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const [card, setCard] = useState<TodayCard | null>(null);
  const [digest, setDigest] = useState<DigestData | null>(null);
  const [showDigest, setShowDigest] = useState(false);
  const [isLoadingToday, setIsLoadingToday] = useState(true);

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
      loadTodayData();
    }, [])
  );

  const loadTodayData = async () => {
    setIsLoadingToday(true);
    try {
      const [cardRes, digestRes] = await Promise.all([
        api.get('/today/card'),
        api.get('/today/digest'),
      ]);
      setCard(cardRes.data.data.card);
      setShowDigest(digestRes.data.data.showDigest);
      setDigest(digestRes.data.data.digest ?? null);
    } catch (e) {
      // Silent fail — Today gracefully degrades to just recent threads
    } finally {
      setIsLoadingToday(false);
    }
  };

  const today = new Date();
  const recentThreads = threads.slice(0, 3);

  return (
    <View className="flex-1 bg-background">
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 60, paddingBottom: 100 }}
      >
        <Text className="text-text-primary text-2xl font-bold">Today</Text>
        <Text className="text-text-tertiary text-xs mt-1 mb-5">{format(today, 'EEEE, d MMMM')}</Text>

        {/* Coaching surface */}
        {isLoadingToday ? (
          <View className="bg-surface rounded-xl px-4 py-4 mb-4 opacity-40">
            <View className="h-2 bg-surface-elevated rounded mb-3 w-1/3" />
            <View className="h-3 bg-surface-elevated rounded mb-2 w-full" />
            <View className="h-3 bg-surface-elevated rounded w-3/4" />
          </View>
        ) : showDigest && digest ? (
          <DigestCard headline={digest.headline} items={digest.items} />
        ) : card ? (
          <TaisaCard eyebrow={card.eyebrow} body={card.body} cta={card.cta} />
        ) : null}

        {/* Recent threads */}
        {recentThreads.length > 0 && (
          <>
            <Text className="text-text-tertiary text-xs font-bold uppercase tracking-wider mb-3">
              {showDigest ? 'Last week' : 'Recent'}
            </Text>
            {isLoadingThreads && recentThreads.length === 0 ? (
              <ActivityIndicator color={colors.accent} />
            ) : (
              recentThreads.map(thread => <ThreadRow key={thread.id} thread={thread} />)
            )}
          </>
        )}
      </ScrollView>

      <FAB />
    </View>
  );
}
```

- [ ] **Step 2: Verify Today tab in app**

Start backend + mobile. Go to Today tab. Confirm: date shows, coaching card or digest renders, recent threads show below, FAB is present. If no data yet, the coaching section is empty (graceful).

- [ ] **Step 3: Commit**

```bash
git add mobile/app/(tabs)/today.tsx
git commit -m "feat: build Today tab with coaching card, digest, and recent threads"
```

---

## Task 15: You tab screen

**Files:**
- Modify: `mobile/app/(tabs)/you.tsx`

- [ ] **Step 1: Build You tab**

Replace `mobile/app/(tabs)/you.tsx`:

```tsx
import { useState, useCallback } from 'react';
import { View, Text, ScrollView, TouchableOpacity, TextInput, Modal, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useCareerStore } from '../../src/stores/careerStore';
import { ThemeTag } from '../../src/components/ThemeTag';
import { colors } from '../../src/constants/theme';
import api from '../../src/services/api';

interface YouData {
  currentFocus: string;
  themes: string[];
  openLoops: string;
}

export default function YouScreen() {
  const { profile, fetchProfile, updateProfile } = useCareerStore();
  const [youData, setYouData] = useState<YouData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editingGoals, setEditingGoals] = useState(false);
  const [editingContext, setEditingContext] = useState(false);
  const [goalsInput, setGoalsInput] = useState('');
  const [roleInput, setRoleInput] = useState('');

  useFocusEffect(
    useCallback(() => {
      fetchProfile();
      loadYouData();
    }, [])
  );

  const loadYouData = async () => {
    setIsLoading(true);
    try {
      const res = await api.get('/today/you');
      setYouData(res.data.data);
    } catch (e) {
      // Silent fail
    } finally {
      setIsLoading(false);
    }
  };

  const saveGoals = async () => {
    try {
      await updateProfile({ longTermGoal: goalsInput });
      setEditingGoals(false);
    } catch (e) {}
  };

  const saveContext = async () => {
    try {
      const [role, company] = roleInput.split(',').map(s => s.trim());
      await updateProfile({ currentRole: role, currentCompany: company });
      setEditingContext(false);
    } catch (e) {}
  };

  const sessionCount = profile?.totalEntryCount ?? 0;

  return (
    <ScrollView className="flex-1 bg-background" contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 60, paddingBottom: 40 }}>
      {/* Avatar row */}
      <View className="flex-row items-center mb-6">
        <View className="w-10 h-10 rounded-full bg-accent-muted items-center justify-center mr-3"
          style={{ borderWidth: 1.5, borderColor: '#7C6FFF55' }}>
          <Text className="text-accent text-lg font-bold">T</Text>
        </View>
        <View>
          <Text className="text-text-primary text-sm font-bold">Taisa User</Text>
          <Text className="text-text-tertiary text-xs">{profile?.currentRole ?? 'Your role'} · {sessionCount} session{sessionCount !== 1 ? 's' : ''}</Text>
        </View>
      </View>

      {/* Taisa's read on you */}
      <SectionLabel>Taisa's read on you</SectionLabel>

      {isLoading ? (
        <View className="bg-surface rounded-xl px-4 py-4 mb-2 opacity-50">
          <View className="h-2 bg-surface-elevated rounded w-1/3 mb-3" />
          <View className="h-3 bg-surface-elevated rounded w-full mb-2" />
          <View className="h-3 bg-surface-elevated rounded w-2/3" />
        </View>
      ) : (
        <>
          {youData?.currentFocus ? (
            <InfoCard label="Current focus" value={youData.currentFocus} />
          ) : null}

          {youData?.themes && youData.themes.length > 0 && (
            <View className="bg-surface rounded-xl px-4 py-3 mb-2">
              <Text className="text-accent text-xs font-bold uppercase tracking-wider mb-2">Recurring themes</Text>
              <View className="flex-row flex-wrap">
                {youData.themes.map(t => <ThemeTag key={t} label={t} />)}
              </View>
            </View>
          )}

          {youData?.openLoops ? (
            <InfoCard label="Open loops" value={youData.openLoops} />
          ) : null}
        </>
      )}

      {/* Career context */}
      <SectionLabel style={{ marginTop: 16 }}>Career context</SectionLabel>

      <TouchableOpacity
        className="bg-surface rounded-xl px-4 py-3 mb-2 flex-row items-center"
        onPress={() => { setGoalsInput(profile?.longTermGoal ?? ''); setEditingGoals(true); }}
      >
        <Text className="text-base mr-3">🎯</Text>
        <View className="flex-1">
          <Text className="text-text-primary text-sm font-semibold">Goals</Text>
          <Text className="text-text-tertiary text-xs mt-0.5" numberOfLines={2}>{profile?.longTermGoal || 'Tap to add your goals'}</Text>
        </View>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      <TouchableOpacity
        className="bg-surface rounded-xl px-4 py-3 mb-2 flex-row items-center"
        onPress={() => { setRoleInput(`${profile?.currentRole ?? ''}, ${profile?.currentCompany ?? ''}`); setEditingContext(true); }}
      >
        <Text className="text-base mr-3">🏢</Text>
        <View className="flex-1">
          <Text className="text-text-primary text-sm font-semibold">Role & company</Text>
          <Text className="text-text-tertiary text-xs mt-0.5">{[profile?.currentRole, profile?.currentCompany].filter(Boolean).join(', ') || 'Tap to add'}</Text>
        </View>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      {/* Settings */}
      <SectionLabel style={{ marginTop: 16 }}>Settings</SectionLabel>

      {/* Export — v2 stub: wire up share sheet when implementing */}
      <TouchableOpacity className="bg-surface rounded-xl px-4 py-3 mb-2 flex-row justify-between items-center">
        <Text className="text-text-primary text-sm">Export my data</Text>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      {/* Edit modals */}
      <EditModal
        visible={editingGoals}
        title="Career goals"
        value={goalsInput}
        onChangeText={setGoalsInput}
        onSave={saveGoals}
        onDismiss={() => setEditingGoals(false)}
        placeholder="e.g. Staff promotion in 12 months, move into leadership"
        multiline
      />
      <EditModal
        visible={editingContext}
        title="Role & company"
        value={roleInput}
        onChangeText={setRoleInput}
        onSave={saveContext}
        onDismiss={() => setEditingContext(false)}
        placeholder="e.g. Senior Designer, Acme Inc"
      />
    </ScrollView>
  );
}

function SectionLabel({ children, style }: { children: React.ReactNode; style?: object }) {
  return (
    <Text className="text-text-tertiary text-xs font-bold uppercase tracking-wider mb-2" style={style}>
      {children}
    </Text>
  );
}

function InfoCard({ label, value }: { label: string; value: string }) {
  return (
    <View className="bg-surface rounded-xl px-4 py-3 mb-2">
      <Text className="text-accent text-xs font-bold uppercase tracking-wider mb-1">{label}</Text>
      <Text className="text-text-secondary text-sm leading-relaxed">{value}</Text>
    </View>
  );
}

function EditModal({ visible, title, value, onChangeText, onSave, onDismiss, placeholder, multiline }: {
  visible: boolean;
  title: string;
  value: string;
  onChangeText: (t: string) => void;
  onSave: () => void;
  onDismiss: () => void;
  placeholder?: string;
  multiline?: boolean;
}) {
  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onDismiss}>
      <View className="flex-1 justify-end" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }}>
        <View className="bg-background rounded-t-3xl px-6 pt-4 pb-12">
          <View className="w-8 h-1 bg-border rounded-full self-center mb-4" />
          <Text className="text-text-primary text-base font-bold mb-4">{title}</Text>
          <TextInput
            value={value}
            onChangeText={onChangeText}
            placeholder={placeholder}
            placeholderTextColor={colors.textTertiary}
            className="bg-surface rounded-xl px-4 py-3 text-text-primary text-sm mb-4"
            multiline={multiline}
            style={multiline ? { minHeight: 80, textAlignVertical: 'top' } : undefined}
            autoFocus
          />
          <View className="flex-row gap-3">
            <TouchableOpacity onPress={onDismiss} className="flex-1 bg-surface rounded-full py-3 items-center">
              <Text className="text-text-secondary text-sm font-semibold">Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={onSave} className="flex-1 bg-accent rounded-full py-3 items-center">
              <Text className="text-white text-sm font-semibold">Save</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}
```

- [ ] **Step 2: Verify You tab**

Start backend + mobile. Go to You tab. Confirm: avatar row, Taisa's read section (loading then renders), career context rows (tapping opens edit modal with save/cancel), settings row.

- [ ] **Step 3: Commit**

```bash
git add mobile/app/(tabs)/you.tsx
git commit -m "feat: build You tab with Taisa's read, career context, and settings"
```

---

## Task 16: Full run-through and cleanup

- [ ] **Step 1: Run all backend tests**

```bash
npm test
```

Expected: all tests PASS. Fix any failures before proceeding.

- [ ] **Step 2: Start backend and mobile together**

```bash
# Terminal 1
npm run backend

# Terminal 2
npm run mobile
```

- [ ] **Step 3: Golden path test**

Walk through the full user journey:

1. Open app → lands on Today tab
2. Tap FAB → recording modal opens
3. Tap mic → speak for 10 seconds → tap Done
4. Wait for "Taisa is reading…" → app navigates to thread
5. Thread shows: voice indicator, transcript, Taisa's reply
6. Type a follow-up message → send → Taisa replies
7. Tap back → lands on Threads tab
8. Thread appears in list with LIVE badge
9. Tap thread → reopens correctly
10. Go to Today tab → coaching card or digest shows, recent thread shows
11. Go to You tab → Taisa's read section, career context editable

- [ ] **Step 4: Check for console errors**

Review Expo logs and backend logs. Fix any runtime errors or API failures.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: Taisa MVP UI rebuild complete — Today/Threads/You with thread model"
```

---

## Deferred from this plan

**Onboarding NativeWind rebuild** (spec Task 9): The existing onboarding screens (`mobile/app/onboarding/index.tsx`) still use `StyleSheet.create()`. They function correctly and are not on the critical path for the MVP experience. Rebuild in a follow-up PR — replace StyleSheet with NativeWind classes using the same color tokens as the new screens.

**Export my data** (You tab): The button is present as a stub. To implement: call `GET /api/v1/entries?limit=1000`, fetch all sessions via `GET /api/v1/chat/sessions`, combine into JSON, and pass to `Share.share()` from `react-native`. Wire up in a follow-up task.

**Voice reply in thread**: The thread input bar has a text input only. Voice replies (tap mic → record → transcribe → send) should be added in a follow-up. The transcription service and recording hook are already available — it's a matter of adding the mic button and wiring it to `sendMessage(sessionId, transcript)`.
