import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../../db/connection';
import { callClaudeJson, MOCK_AI } from './client';
import { buildReviewAnalystSystem, buildReviewAnalystUser } from '../../prompts/system/performanceReviewAnalyst';
import type { CareerProfile, ReviewFeedback, Goal } from '@taisa/shared';

interface ReviewAnalysisResult {
  extractedFeedback: ReviewFeedback;
  suggestedGoals: Goal[];
}

export async function analyzePerformanceReview(params: {
  reviewId: string;
  reviewText: string;
  reviewerContext: string;
  userId: string;
}): Promise<ReviewAnalysisResult> {
  const { reviewId, reviewText, reviewerContext, userId } = params;
  const db = getDb();

  // Load profile
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
    reminderTimes: [],
    dominantThemes: [],
    growthTrajectory: profileRow.growth_trajectory,
    openActionItemCount: profileRow.open_action_item_count,
    totalEntryCount: profileRow.total_entry_count,
    lastEntryAt: profileRow.last_entry_at,
  };

  // Load recent themes
  const recentThemes = db.prepare(
    'SELECT label, count FROM career_themes WHERE user_id = ? ORDER BY count DESC LIMIT 20'
  ).all(userId) as any[];

  // Build a recent journal summary (last 5 coach notes)
  const recentNotes = db.prepare(
    "SELECT ea.coach_note FROM entry_analyses ea JOIN journal_entries je ON ea.entry_id = je.id WHERE je.user_id = ? ORDER BY je.recorded_at DESC LIMIT 5"
  ).all(userId) as any[];
  const recentJournalSummary = recentNotes.map((n: any) => n.coach_note).filter(Boolean).join(' | ');

  // Call Claude (or return mock when MOCK_AI=true)
  const result: ReviewAnalysisResult = MOCK_AI
    ? { extractedFeedback: {} as any, suggestedGoals: [] }
    : await callClaudeJson<ReviewAnalysisResult>({
        system: buildReviewAnalystSystem(profile),
        userMessage: buildReviewAnalystUser({
          reviewText,
          reviewerContext,
          recentThemes: recentThemes.map(t => ({ label: t.label, count: t.count })),
          recentJournalSummary,
        }),
        temperature: 0.4,
        maxTokens: 4096,
      });

  const now = new Date().toISOString();

  // Persist suggested goals and milestones
  const insertGoal = db.prepare(`INSERT INTO goals (
    id, user_id, source_review_id, title, description, suggested_by_ai,
    priority, status, related_themes, progress_percent, created_at, updated_at, target_date
  ) VALUES (?, ?, ?, ?, ?, 1, ?, 'active', ?, 0, ?, ?, ?)`);

  const insertMilestone = db.prepare(`INSERT INTO milestones (id, goal_id, title, status, evidence_entry_ids, created_at, updated_at)
    VALUES (?, ?, ?, 'pending', '[]', ?, ?)`);

  const savedGoals: Goal[] = [];

  for (const goal of (result.suggestedGoals || [])) {
    const goalId = uuidv4();
    insertGoal.run(
      goalId, userId, reviewId,
      goal.title, goal.description,
      goal.priority || 'medium',
      JSON.stringify(goal.relatedThemes || []),
      now, now,
      goal.targetDate || null,
    );

    const savedMilestones = [];
    for (const milestone of (goal.milestones || [])) {
      const milestoneId = uuidv4();
      insertMilestone.run(milestoneId, goalId, milestone.title, now, now);
      savedMilestones.push({ id: milestoneId, goalId, title: milestone.title, status: 'pending' as const, evidenceEntryIds: [] });
    }

    savedGoals.push({ ...goal, id: goalId, userId, sourceReviewId: reviewId, progressPercent: 0, createdAt: now, milestones: savedMilestones });
  }

  // Update review record with extracted data
  db.prepare('UPDATE performance_reviews SET extracted_feedback = ?, suggested_goals = ? WHERE id = ?')
    .run(JSON.stringify(result.extractedFeedback), JSON.stringify(savedGoals.map(g => g.id)), reviewId);

  return {
    extractedFeedback: result.extractedFeedback,
    suggestedGoals: savedGoals,
  };
}
