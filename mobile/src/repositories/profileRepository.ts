import type { LocalCareerProfile } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { parseStringArray } from './mapping';
import {
  IdempotencyConflictError,
  claimMutation,
  requireExactlyOneAffectedRow,
} from './mutationReceipt';

interface ProfileRow {
  id: string;
  current_role: string | null;
  current_company: string | null;
  industry: string | null;
  years_of_experience: number | null;
  career_stage: LocalCareerProfile['careerStage'];
  current_focus_area: string | null;
  short_term_goal: string | null;
  long_term_goal: string | null;
  coaching_style: LocalCareerProfile['coachingStyle'];
  accountability_level: LocalCareerProfile['accountabilityLevel'];
  reminder_times_json: string;
  created_at: string;
  updated_at: string;
}

const PROFILE_COLUMNS = `id, current_role, current_company, industry, years_of_experience,
  career_stage, current_focus_area, short_term_goal, long_term_goal, coaching_style,
  accountability_level, reminder_times_json, created_at, updated_at`;

function mapProfile(row: ProfileRow): LocalCareerProfile {
  return {
    id: row.id,
    currentRole: row.current_role,
    currentCompany: row.current_company,
    industry: row.industry,
    yearsOfExperience: row.years_of_experience,
    careerStage: row.career_stage,
    currentFocusArea: row.current_focus_area,
    shortTermGoal: row.short_term_goal,
    longTermGoal: row.long_term_goal,
    coachingStyle: row.coaching_style,
    accountabilityLevel: row.accountability_level,
    reminderTimes: parseStringArray(row.reminder_times_json, 'profile.reminder_times_json'),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function profileParams(profile: LocalCareerProfile) {
  return {
    $id: profile.id,
    $currentRole: profile.currentRole,
    $currentCompany: profile.currentCompany,
    $industry: profile.industry,
    $yearsOfExperience: profile.yearsOfExperience,
    $careerStage: profile.careerStage,
    $currentFocusArea: profile.currentFocusArea,
    $shortTermGoal: profile.shortTermGoal,
    $longTermGoal: profile.longTermGoal,
    $coachingStyle: profile.coachingStyle,
    $accountabilityLevel: profile.accountabilityLevel,
    $reminderTimesJson: JSON.stringify(profile.reminderTimes),
    $createdAt: profile.createdAt,
    $updatedAt: profile.updatedAt,
  };
}

export async function insertProfile(
  transaction: RepositoryTransaction,
  profile: LocalCareerProfile,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'profile', profile.id, 'insert', profile))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO profile (${PROFILE_COLUMNS})
     VALUES ($id, $currentRole, $currentCompany, $industry, $yearsOfExperience,
       $careerStage, $currentFocusArea, $shortTermGoal, $longTermGoal, $coachingStyle,
       $accountabilityLevel, $reminderTimesJson, $createdAt, $updatedAt)`,
    profileParams(profile),
  );
}

export async function getProfile(
  database: RepositoryConnection,
  id: string,
): Promise<LocalCareerProfile | null> {
  const row = await database.getFirstAsync<ProfileRow>(
    `SELECT ${PROFILE_COLUMNS} FROM profile WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapProfile(row);
}

export async function updateProfile(
  transaction: RepositoryTransaction,
  profile: LocalCareerProfile,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'profile', profile.id, 'update', profile))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE profile SET
       current_role = $currentRole,
       current_company = $currentCompany,
       industry = $industry,
       years_of_experience = $yearsOfExperience,
       career_stage = $careerStage,
       current_focus_area = $currentFocusArea,
       short_term_goal = $shortTermGoal,
       long_term_goal = $longTermGoal,
       coaching_style = $coachingStyle,
       accountability_level = $accountabilityLevel,
       reminder_times_json = $reminderTimesJson,
       created_at = $createdAt,
       updated_at = $updatedAt
     WHERE id = $id`,
    profileParams(profile),
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing profile');
}

export async function listProfiles(database: RepositoryConnection): Promise<LocalCareerProfile[]> {
  const rows = await database.getAllAsync<ProfileRow>(
    `SELECT ${PROFILE_COLUMNS} FROM profile ORDER BY created_at, id`,
  );
  return rows.map(mapProfile);
}

export { IdempotencyConflictError };
