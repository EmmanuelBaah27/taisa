import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db/connection';
import { analyzePerformanceReview } from '../services/claude/performanceReviewAgent';
import { parseAnthropicError } from '../services/claude/client';
import { logRequestError } from '../middleware/requestContext';

const router = Router();

// POST /api/v1/reviews
router.post('/', async (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });

  const { rawText, reviewerContext } = req.body;
  if (!rawText) return res.status(400).json({ success: false, error: { code: 'MISSING_TEXT', message: 'rawText required' } });

  const db = getDb();
  const reviewId = uuidv4();
  const now = new Date().toISOString();

  // Create review record first (analysis fills it in)
  db.prepare(`INSERT INTO performance_reviews (id, user_id, created_at, reviewer_context, raw_text, extracted_feedback, suggested_goals)
    VALUES (?, ?, ?, ?, ?, '{}', '[]')`
  ).run(reviewId, userId, now, reviewerContext || 'Performance review', rawText);

  try {
    const result = await analyzePerformanceReview({ reviewId, reviewText: rawText, reviewerContext: reviewerContext || 'Performance review', userId });

    const row = db.prepare('SELECT * FROM performance_reviews WHERE id = ?').get(reviewId) as any;
    res.status(201).json({
      success: true,
      data: {
        id: row.id,
        userId: row.user_id,
        createdAt: row.created_at,
        reviewerContext: row.reviewer_context,
        rawText: row.raw_text,
        extractedFeedback: result.extractedFeedback,
        suggestedGoals: result.suggestedGoals,
      },
    });
  } catch (error: any) {
    const { code } = parseAnthropicError(error);
    logRequestError(req, code, error);
    res.status(500).json({
      success: false,
      error: { code, message: 'Unable to analyze performance review' },
    });
  }
});

// GET /api/v1/reviews
router.get('/', (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });

  const db = getDb();
  const rows = db.prepare('SELECT * FROM performance_reviews WHERE user_id = ? ORDER BY created_at DESC').all(userId) as any[];

  res.json({
    success: true,
    data: rows.map(r => ({
      id: r.id,
      userId: r.user_id,
      createdAt: r.created_at,
      reviewerContext: r.reviewer_context,
      extractedFeedback: JSON.parse(r.extracted_feedback || '{}'),
      suggestedGoalCount: JSON.parse(r.suggested_goals || '[]').length,
    })),
  });
});

// GET /api/v1/reviews/:id
router.get('/:id', (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });

  const db = getDb();
  const row = db.prepare('SELECT * FROM performance_reviews WHERE id = ? AND user_id = ?').get(req.params.id, userId) as any;
  if (!row) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Review not found' } });

  const goalIds: string[] = JSON.parse(row.suggested_goals || '[]');
  const goals = goalIds.length > 0
    ? (db.prepare(`SELECT * FROM goals WHERE id IN (${goalIds.map(() => '?').join(',')})`) .all(...goalIds) as any[]).map(g => ({
        id: g.id, title: g.title, description: g.description, priority: g.priority,
        status: g.status, progressPercent: g.progress_percent, suggestedByAI: !!g.suggested_by_ai,
        milestones: (db.prepare('SELECT * FROM milestones WHERE goal_id = ?').all(g.id) as any[]),
      }))
    : [];

  res.json({
    success: true,
    data: {
      id: row.id, userId: row.user_id, createdAt: row.created_at,
      reviewerContext: row.reviewer_context, rawText: row.raw_text,
      extractedFeedback: JSON.parse(row.extracted_feedback || '{}'),
      suggestedGoals: goals,
    },
  });
});

export default router;
