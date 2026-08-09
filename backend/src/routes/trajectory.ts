import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db/connection';
import { callClaudeJson, MOCK_AI, parseAnthropicError } from '../services/claude/client';
import { buildTrajectorySystem, buildTrajectoryUser } from '../prompts/system/trajectoryAnalyst';
import { logRequestError } from '../middleware/requestContext';

const router = Router();

// GET /api/v1/trajectory
router.get('/', (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });

  const db = getDb();
  const period = req.query.period || '30d';

  const row = db.prepare(
    'SELECT * FROM trajectory_snapshots WHERE user_id = ? ORDER BY generated_at DESC LIMIT 1'
  ).get(userId) as any;

  if (!row) return res.json({ success: true, data: null });

  res.json({
    success: true,
    data: {
      id: row.id, userId: row.user_id, generatedAt: row.generated_at,
      periodStart: row.period_start, periodEnd: row.period_end,
      narrativeSummary: row.narrative_summary,
      keyThemes: JSON.parse(row.key_themes || '[]'),
      momentumHistory: JSON.parse(row.momentum_history || '[]'),
      winCount: row.win_count, challengeCount: row.challenge_count,
      resolvedChallengeCount: row.resolved_challenge_count,
      growthObservations: JSON.parse(row.growth_observations || '[]'),
      suggestedFocusAreas: JSON.parse(row.suggested_focus_areas || '[]'),
      goalProgressSummaries: JSON.parse(row.goal_progress_summaries || '[]'),
    },
  });
});

// POST /api/v1/trajectory/generate
router.post('/generate', async (req, res) => {
  const userId = req.headers['x-user-id'] as string;
  if (!userId) return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'x-user-id header required' } });

  const db = getDb();
  const period = (req.query.period as string) || '30d';
  const daysBack = period === 'all' ? 3650 : period === '90d' ? 90 : 30;
  const periodStart = new Date(Date.now() - daysBack * 86400000).toISOString();
  const periodEnd = new Date().toISOString();

  // Load profile
  const profileRow = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  if (!profileRow) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Profile not found' } });

  const profile = {
    id: profileRow.id, userId: profileRow.id,
    currentRole: profileRow.current_role, currentCompany: profileRow.current_company,
    industry: profileRow.industry, yearsOfExperience: profileRow.years_of_experience,
    careerStage: profileRow.career_stage, shortTermGoal: profileRow.short_term_goal,
    longTermGoal: profileRow.long_term_goal, currentFocusArea: profileRow.current_focus_area,
    coachingStyle: profileRow.coaching_style, accountabilityLevel: profileRow.accountability_level,
    reminderTimes: [], dominantThemes: [], growthTrajectory: profileRow.growth_trajectory,
    openActionItemCount: profileRow.open_action_item_count, totalEntryCount: profileRow.total_entry_count,
    lastEntryAt: profileRow.last_entry_at, createdAt: profileRow.created_at, updatedAt: profileRow.updated_at,
  };

  // Load entries in period
  const entries = db.prepare(
    'SELECT je.*, ea.* FROM journal_entries je LEFT JOIN entry_analyses ea ON je.analysis_id = ea.id WHERE je.user_id = ? AND je.recorded_at >= ? ORDER BY je.recorded_at ASC'
  ).all(userId, periodStart) as any[];

  if (entries.length === 0) {
    return res.json({ success: true, data: null, message: 'Not enough entries to generate trajectory' });
  }

  const momentumHistory = entries.map(e => ({
    recordedAt: e.recorded_at,
    signal: e.momentum_signal || 'steady',
    sentiment: e.sentiment || 'neutral',
    energyLevel: e.energy_level || 3,
  }));

  const themeFrequency = (db.prepare(
    'SELECT label, count, first_seen_at FROM career_themes WHERE user_id = ? ORDER BY count DESC LIMIT 20'
  ).all(userId) as any[]).map(t => ({ label: t.label, count: t.count, firstSeenAt: t.first_seen_at }));

  const allWins = entries.flatMap(e => JSON.parse(e.wins || '[]').map((w: any) => ({ ...w, date: e.recorded_at })));
  const allChallenges = entries.flatMap(e => JSON.parse(e.challenges || '[]').map((c: any) => ({ ...c, date: e.recorded_at })));

  const openActionItems = (db.prepare(
    "SELECT title, created_at, priority FROM action_items WHERE user_id = ? AND status = 'open' ORDER BY created_at ASC"
  ).all(userId) as any[]).map(a => ({ title: a.title, createdAt: a.created_at, priority: a.priority }));

  const activeGoals = (db.prepare(
    "SELECT * FROM goals WHERE user_id = ? AND status = 'active'"
  ).all(userId) as any[]).map(g => ({
    id: g.id, title: g.title, description: g.description,
    currentProgress: g.progress_percent,
    relatedThemes: JSON.parse(g.related_themes || '[]'),
  }));

  const recentCoachNotes = entries.slice(-5).map(e => e.coach_note).filter(Boolean);

  try {
    const result = MOCK_AI
      ? {
          narrativeSummary: '[Mock] Trajectory analysis requires Anthropic API credits — top up at console.anthropic.com.',
          keyThemes: [],
          winCount: allWins.length,
          challengeCount: allChallenges.length,
          resolvedChallengeCount: 0,
          growthObservations: [],
          suggestedFocusAreas: [],
          goalProgressSummaries: [],
        }
      : await callClaudeJson<any>({
      system: buildTrajectorySystem(profile as any),
      userMessage: buildTrajectoryUser({
        entryCount: entries.length, periodStart, periodEnd,
        momentumHistory, themeFrequency,
        winsSummary: allWins.slice(0, 20),
        challengesSummary: allChallenges.slice(0, 20),
        openActionItems, activeGoals, recentCoachNotes,
      }),
      temperature: 0.5,
      maxTokens: 4096,
    });

    const snapshotId = uuidv4();
    const now = new Date().toISOString();

    db.prepare(`INSERT INTO trajectory_snapshots (
      id, user_id, generated_at, period_start, period_end, narrative_summary,
      key_themes, momentum_history, win_count, challenge_count, resolved_challenge_count,
      growth_observations, suggested_focus_areas, goal_progress_summaries
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      snapshotId, userId, now, periodStart, periodEnd,
      result.narrativeSummary || '',
      JSON.stringify(result.keyThemes || []),
      JSON.stringify(momentumHistory),
      result.winCount || allWins.length,
      result.challengeCount || allChallenges.length,
      result.resolvedChallengeCount || 0,
      JSON.stringify(result.growthObservations || []),
      JSON.stringify(result.suggestedFocusAreas || []),
      JSON.stringify(result.goalProgressSummaries || []),
    );

    // Update goal progress from trajectory assessment
    for (const gps of (result.goalProgressSummaries || [])) {
      if (gps.goalId && gps.progressPercent !== undefined) {
        db.prepare('UPDATE goals SET progress_percent = ?, updated_at = ? WHERE id = ? AND user_id = ?')
          .run(gps.progressPercent, now, gps.goalId, userId);
      }
    }

    res.json({ success: true, data: { id: snapshotId, ...result, periodStart, periodEnd, momentumHistory } });
  } catch (error: any) {
    const { code } = parseAnthropicError(error);
    logRequestError(req, code, error);
    res.status(500).json({
      success: false,
      error: { code, message: 'Unable to generate trajectory' },
    });
  }
});

export default router;
