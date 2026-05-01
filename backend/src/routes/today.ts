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

    const patternCount = items.filter(i => i.type === 'pattern').length;
    const headline = `${sessionCount} session${sessionCount !== 1 ? 's' : ''} · ${patternCount} pattern${patternCount !== 1 ? 's' : ''} · ${recentWins.length} win${recentWins.length !== 1 ? 's' : ''}`;

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
