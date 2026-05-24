import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../../db/connection';
import { callClaudeJson, MODEL, MOCK_AI } from './client';
import { buildJournalProcessorSystem, buildJournalProcessorUser } from '../../prompts/system/journalProcessor';
import type { EntryAnalysis, CareerProfile } from '@taisa/shared';

const MOCK_RESULT = {
  summary: '[Mock] Entry received. Add Anthropic credits at console.anthropic.com to enable real analysis.',
  sentiment: 'neutral' as const,
  energyLevel: 3 as const,
  wins: [] as any[],
  challenges: [] as any[],
  decisions: [] as any[],
  actionItems: [] as any[],
  themes: [] as any[],
  coachNote: 'Entry saved successfully. Top up Anthropic credits at console.anthropic.com to activate AI coaching.',
  growthAreas: [] as string[],
  momentumSignal: 'steady' as const,
  patternFlags: [] as any[],
  accountabilityCallouts: [] as string[],
  goalAssessments: [] as any[],
};

export async function analyzeEntry(entryId: string, userId: string): Promise<EntryAnalysis> {
  const db = getDb();

  // Load entry
  const entry = db.prepare('SELECT * FROM journal_entries WHERE id = ? AND user_id = ?').get(entryId, userId) as any;
  if (!entry) throw new Error('Entry not found');

  const transcript = entry.edited_transcript || entry.raw_transcript;

  // Load career profile
  const profileRow = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as any;
  if (!profileRow) throw new Error('User profile not found');

  const profile: CareerProfile = {
    id: profileRow.id,
    userId: profileRow.id,
    createdAt: profileRow.created_at,
    updatedAt: profileRow.updated_at,
    currentRole: profileRow.current_role,
    currentCompany: profileRow.current_company,
    industry: profileRow.industry,
    yearsOfExperience: profileRow.years_of_experience,
    careerStage: profileRow.career_stage,
    shortTermGoal: profileRow.short_term_goal,
    longTermGoal: profileRow.long_term_goal,
    currentFocusArea: profileRow.current_focus_area,
    coachingStyle: profileRow.coaching_style,
    accountabilityLevel: profileRow.accountability_level,
    reminderTimes: JSON.parse(profileRow.reminder_times || '[]'),
    dominantThemes: JSON.parse(profileRow.dominant_themes || '[]'),
    growthTrajectory: profileRow.growth_trajectory,
    openActionItemCount: profileRow.open_action_item_count,
    totalEntryCount: profileRow.total_entry_count,
    lastEntryAt: profileRow.last_entry_at,
  };

  // Load open action items
  const openActionItems = db.prepare(
    "SELECT title, due_context, priority, created_at FROM action_items WHERE user_id = ? AND status = 'open' ORDER BY created_at DESC LIMIT 10"
  ).all(userId) as any[];

  // Load recent themes
  const recentThemes = db.prepare(
    'SELECT label, count FROM career_themes WHERE user_id = ? ORDER BY count DESC LIMIT 20'
  ).all(userId) as any[];

  // Load active goals with milestones
  const activeGoals = (db.prepare(
    "SELECT * FROM goals WHERE user_id = ? AND status = 'active'"
  ).all(userId) as any[]).map(g => ({
    id: g.id,
    title: g.title,
    description: g.description,
    relatedThemes: JSON.parse(g.related_themes || '[]'),
    progressPercent: g.progress_percent,
    milestones: (db.prepare('SELECT * FROM milestones WHERE goal_id = ?').all(g.id) as any[]).map(m => ({
      id: m.id,
      title: m.title,
      status: m.status,
    })),
  }));

  // Call Claude (or return mock data when MOCK_AI=true)
  const system = buildJournalProcessorSystem(profile);
  const userMessage = buildJournalProcessorUser({
    transcript,
    recordedAt: entry.recorded_at,
    durationSeconds: entry.audio_duration_seconds,
    entryId,
    openActionItems: openActionItems.map(a => ({ title: a.title, dueContext: a.due_context, priority: a.priority, createdAt: a.created_at })),
    recentThemes: recentThemes.map(t => ({ label: t.label, count: t.count })),
    activeGoals,
  });

  const result = MOCK_AI
    ? MOCK_RESULT
    : await callClaudeJson<Omit<EntryAnalysis, 'id' | 'entryId' | 'createdAt' | 'modelVersion'>>({
        system,
        userMessage,
        temperature: 0.3,
        maxTokens: 4096,
      });

  const analysisId = uuidv4();
  const now = new Date().toISOString();

  // Fix placeholder IDs in action items
  const actionItems = (result.actionItems || []).map((item: any) => ({
    ...item,
    id: uuidv4(),
    sourceEntryId: entryId,
  }));

  // Persist analysis
  db.prepare(`INSERT INTO entry_analyses (
    id, entry_id, created_at, model_version, summary, sentiment, energy_level,
    wins, challenges, decisions, action_items, themes, coach_note, growth_areas,
    momentum_signal, pattern_flags, accountability_callouts, goal_assessments
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    analysisId, entryId, now, MODEL,
    result.summary || '', result.sentiment || 'neutral', result.energyLevel || 3,
    JSON.stringify(result.wins || []),
    JSON.stringify(result.challenges || []),
    JSON.stringify(result.decisions || []),
    JSON.stringify(actionItems),
    JSON.stringify(result.themes || []),
    result.coachNote || '',
    JSON.stringify(result.growthAreas || []),
    result.momentumSignal || 'steady',
    JSON.stringify(result.patternFlags || []),
    JSON.stringify(result.accountabilityCallouts || []),
    JSON.stringify(result.goalAssessments || []),
  );

  // Link analysis to entry
  db.prepare("UPDATE journal_entries SET analysis_id = ?, status = 'complete', updated_at = ? WHERE id = ?")
    .run(analysisId, now, entryId);

  // Persist action items to action_items table
  const insertItem = db.prepare(`INSERT INTO action_items (id, user_id, source_entry_id, title, due_context, priority, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?)`);
  for (const item of actionItems) {
    insertItem.run(item.id, userId, entryId, item.title, item.dueContext || null, item.priority, now, now);
  }

  // Update action item count on user
  const openCount = (db.prepare("SELECT COUNT(*) as count FROM action_items WHERE user_id = ? AND status = 'open'").get(userId) as any).count;
  db.prepare('UPDATE users SET open_action_item_count = ?, updated_at = ? WHERE id = ?').run(openCount, now, userId);

  // Update career themes
  for (const theme of (result.themes || [])) {
    db.prepare(`INSERT INTO career_themes (id, user_id, label, count, first_seen_at, last_seen_at, trend)
      VALUES (?, ?, ?, 1, ?, ?, 'stable')
      ON CONFLICT(user_id, label) DO UPDATE SET count = count + 1, last_seen_at = excluded.last_seen_at`
    ).run(uuidv4(), userId, theme.label, now, now);
  }

  // Update goal progress based on goal assessments
  for (const assessment of (result.goalAssessments || [])) {
    if (assessment.goalId && assessment.progressDelta !== 0) {
      db.prepare(`UPDATE goals SET
        progress_percent = MIN(100, MAX(0, progress_percent + ?)),
        updated_at = ?
      WHERE id = ? AND user_id = ?`
      ).run(assessment.progressDelta, now, assessment.goalId, userId);

      // Mark achieved milestones
      for (const milestoneId of (assessment.milestonesAchieved || [])) {
        db.prepare("UPDATE milestones SET status = 'complete', updated_at = ? WHERE id = ?").run(now, milestoneId);
      }
    }
  }

  // Check if goal is fully achieved
  db.prepare(`UPDATE goals SET status = 'achieved', updated_at = ? WHERE user_id = ? AND progress_percent >= 100 AND status = 'active'`).run(now, userId);

  return {
    id: analysisId,
    entryId,
    createdAt: now,
    modelVersion: MODEL,
    summary: result.summary || '',
    sentiment: result.sentiment || 'neutral',
    energyLevel: result.energyLevel || 3,
    wins: result.wins || [],
    challenges: result.challenges || [],
    decisions: result.decisions || [],
    actionItems,
    themes: result.themes || [],
    coachNote: result.coachNote || '',
    growthAreas: result.growthAreas || [],
    momentumSignal: result.momentumSignal || 'steady',
    patternFlags: result.patternFlags || [],
    accountabilityCallouts: result.accountabilityCallouts || [],
    goalAssessments: result.goalAssessments || [],
  };
}
