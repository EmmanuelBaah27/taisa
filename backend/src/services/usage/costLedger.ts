import { randomUUID } from 'crypto';
import path from 'path';
import Database from 'better-sqlite3';
import type { UsageReceipt } from '@taisa/shared';

export interface CostCeilings {
  perRequestUsd: number;
  dailyUsd: number;
  monthlyUsd: number;
}

export interface RecordedUsage {
  recordedAt: string;
  receipt: UsageReceipt;
}

export interface CostReservation {
  beginProviderInvocation(): void;
  commit(receipt: UsageReceipt): void;
  consumeEstimate(): void;
  release(): void;
}

export interface AttemptEstimate {
  attemptId: 'primary' | 'fallback';
  receipt: UsageReceipt;
}

export interface AttemptSettlement {
  attemptId: AttemptEstimate['attemptId'];
  receipt?: UsageReceipt;
}

export interface MultiAttemptCostReservation {
  beginAttempt(attemptId: AttemptEstimate['attemptId']): void;
  settleAttempt(settlement: AttemptSettlement): void;
  release(): void;
}

export interface UsageLedger {
  recordUsage(receipt: UsageReceipt, recordedAt?: Date): void;
  listUsage(): RecordedUsage[];
  reserveUsage(
    estimatedReceipt: UsageReceipt,
    ceilings: CostCeilings,
    reservedAt?: Date,
  ): CostReservation;
  reserveAttempts(
    estimates: readonly AttemptEstimate[],
    ceilings: CostCeilings,
    reservedAt?: Date,
  ): MultiAttemptCostReservation;
}

export interface CostLedgerOptions {
  databasePath?: string;
}

interface UsageRow {
  recorded_at: string;
  provider: UsageReceipt['provider'];
  model: string;
  input_tokens: number | null;
  output_tokens: number | null;
  audio_seconds: number | null;
  estimated_cost_usd: number;
}

interface ReservationRow extends UsageRow {
  id: string;
  status: 'pending' | 'in_flight';
}

interface AttemptReservationRow {
  request_id: string;
  attempt_id: AttemptEstimate['attemptId'];
  provider: UsageReceipt['provider'];
  model: string;
  input_tokens: number | null;
  output_tokens: number | null;
  estimated_cost_usd: number;
  status: 'pending' | 'in_flight' | 'settled';
  recorded_at: string;
}

export class CostLimitError extends Error {
  readonly code = 'COST_LIMIT_EXCEEDED';

  constructor() {
    super('Configured AI cost ceiling would be exceeded');
    this.name = 'CostLimitError';
  }
}

export class CostConfigurationError extends Error {
  readonly code = 'COST_CONFIGURATION_ERROR';

  constructor(name: string) {
    super(`${name} must be configured as a non-negative number`);
    this.name = 'CostConfigurationError';
  }
}

export class UsageExceedsReservationError extends Error {
  readonly code = 'USAGE_EXCEEDS_RESERVATION';

  constructor(readonly reservedUsd: number, readonly actualUsd: number) {
    super('Actual provider usage exceeded its conservative reservation');
    this.name = 'UsageExceedsReservationError';
  }
}

function finiteNonNegative(value: number, name: string): number {
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number`);
  }
  return value;
}

function sanitizeOptionalNumber(value: number | undefined, name: string): number | undefined {
  return value === undefined ? undefined : finiteNonNegative(value, name);
}

function sanitizeReceipt(receipt: UsageReceipt): UsageReceipt {
  return {
    provider: receipt.provider,
    model: receipt.model,
    ...(receipt.inputTokens === undefined
      ? {}
      : { inputTokens: sanitizeOptionalNumber(receipt.inputTokens, 'inputTokens') }),
    ...(receipt.outputTokens === undefined
      ? {}
      : { outputTokens: sanitizeOptionalNumber(receipt.outputTokens, 'outputTokens') }),
    ...(receipt.audioSeconds === undefined
      ? {}
      : { audioSeconds: sanitizeOptionalNumber(receipt.audioSeconds, 'audioSeconds') }),
    estimatedCostUsd: finiteNonNegative(receipt.estimatedCostUsd, 'estimatedCostUsd'),
  };
}

function receiptParams(id: string, receipt: UsageReceipt, recordedAt: string) {
  const sanitized = sanitizeReceipt(receipt);
  return {
    id,
    recordedAt,
    provider: sanitized.provider,
    model: sanitized.model,
    inputTokens: sanitized.inputTokens ?? null,
    outputTokens: sanitized.outputTokens ?? null,
    audioSeconds: sanitized.audioSeconds ?? null,
    estimatedCostUsd: sanitized.estimatedCostUsd,
  };
}

function receiptFromRow(row: UsageRow): UsageReceipt {
  return {
    provider: row.provider,
    model: row.model,
    ...(row.input_tokens === null ? {} : { inputTokens: row.input_tokens }),
    ...(row.output_tokens === null ? {} : { outputTokens: row.output_tokens }),
    ...(row.audio_seconds === null ? {} : { audioSeconds: row.audio_seconds }),
    estimatedCostUsd: row.estimated_cost_usd,
  };
}

function receiptFromAttemptRow(row: AttemptReservationRow): UsageReceipt {
  return {
    provider: row.provider,
    model: row.model,
    ...(row.input_tokens === null ? {} : { inputTokens: row.input_tokens }),
    ...(row.output_tokens === null ? {} : { outputTokens: row.output_tokens }),
    estimatedCostUsd: row.estimated_cost_usd,
  };
}

function sanitizeAttemptEstimates(
  estimates: readonly AttemptEstimate[],
): ReadonlyMap<AttemptEstimate['attemptId'], UsageReceipt> {
  if (estimates.length !== 2) {
    throw new Error('Multi-attempt reservations require exactly one primary and one fallback');
  }

  const sanitized = new Map<AttemptEstimate['attemptId'], UsageReceipt>();
  for (const estimate of estimates) {
    if (estimate.attemptId !== 'primary' && estimate.attemptId !== 'fallback') continue;
    if (sanitized.has(estimate.attemptId)) {
      throw new Error('Multi-attempt reservations require exactly one primary and one fallback');
    }
    sanitized.set(estimate.attemptId, sanitizeReceipt(estimate.receipt));
  }

  if (sanitized.size !== 2 || !sanitized.has('primary') || !sanitized.has('fallback')) {
    throw new Error('Multi-attempt reservations require exactly one primary and one fallback');
  }
  return sanitized;
}

function utcPeriod(date: Date) {
  const dayStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayEnd = new Date(dayStart);
  dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);
  const monthStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
  const monthEnd = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
  return {
    dayStart: dayStart.toISOString(),
    dayEnd: dayEnd.toISOString(),
    monthStart: monthStart.toISOString(),
    monthEnd: monthEnd.toISOString(),
  };
}

export class CostLedger implements UsageLedger {
  private readonly database: Database.Database;

  constructor(options: CostLedgerOptions = {}) {
    const databasePath = options.databasePath ?? ':memory:';
    this.database = new Database(databasePath);
    this.database.pragma('busy_timeout = 5000');
    this.database.pragma('journal_mode = WAL');
    this.database.pragma('foreign_keys = ON');
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS usage_receipts (
        id TEXT PRIMARY KEY,
        recorded_at TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER,
        output_tokens INTEGER,
        audio_seconds REAL,
        estimated_cost_usd REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS cost_reservations (
        id TEXT PRIMARY KEY,
        recorded_at TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER,
        output_tokens INTEGER,
        audio_seconds REAL,
        estimated_cost_usd REAL NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'in_flight'))
      );
      CREATE TABLE IF NOT EXISTS cost_request_reservations (
        id TEXT PRIMARY KEY,
        recorded_at TEXT NOT NULL,
        estimated_cost_usd REAL NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'in_flight'))
      );
      CREATE TABLE IF NOT EXISTS cost_attempt_reservations (
        request_id TEXT NOT NULL,
        attempt_id TEXT NOT NULL CHECK(attempt_id IN ('primary', 'fallback')),
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER,
        output_tokens INTEGER,
        estimated_cost_usd REAL NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'in_flight', 'settled')),
        PRIMARY KEY (request_id, attempt_id),
        FOREIGN KEY (request_id) REFERENCES cost_request_reservations(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_usage_receipts_recorded_at
        ON usage_receipts(recorded_at);
      CREATE INDEX IF NOT EXISTS idx_cost_reservations_recorded_at
        ON cost_reservations(recorded_at);
      CREATE INDEX IF NOT EXISTS idx_cost_request_reservations_recorded_at
        ON cost_request_reservations(recorded_at);
    `);
    this.reconcileInterruptedReservations();
  }

  private reconcileInterruptedReservations(): void {
    this.database.transaction(() => {
      this.database.prepare(`
        INSERT OR IGNORE INTO usage_receipts (
          id, recorded_at, provider, model, input_tokens, output_tokens,
          audio_seconds, estimated_cost_usd
        )
        SELECT id, recorded_at, provider, model, input_tokens, output_tokens,
          audio_seconds, estimated_cost_usd
        FROM cost_reservations WHERE status = 'in_flight'
      `).run();
      this.database.prepare('DELETE FROM cost_reservations').run();

      const interruptedAttempts = this.database.prepare(`
        SELECT attempts.request_id, attempts.attempt_id, attempts.provider, attempts.model,
          attempts.input_tokens, attempts.output_tokens, attempts.estimated_cost_usd,
          attempts.status, requests.recorded_at
        FROM cost_attempt_reservations AS attempts
        JOIN cost_request_reservations AS requests ON requests.id = attempts.request_id
        WHERE attempts.status = 'in_flight'
        ORDER BY requests.recorded_at, requests.rowid,
          CASE attempts.attempt_id WHEN 'primary' THEN 0 ELSE 1 END
      `).all() as AttemptReservationRow[];
      const insertUsage = this.database.prepare(`
        INSERT INTO usage_receipts (
          id, recorded_at, provider, model, input_tokens, output_tokens,
          audio_seconds, estimated_cost_usd
        ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)
      `);
      for (const attempt of interruptedAttempts) {
        const receipt = receiptFromAttemptRow(attempt);
        insertUsage.run(
          randomUUID(),
          attempt.recorded_at,
          receipt.provider,
          receipt.model,
          receipt.inputTokens ?? null,
          receipt.outputTokens ?? null,
          receipt.estimatedCostUsd,
        );
      }
      this.database.prepare('DELETE FROM cost_request_reservations').run();
    }).immediate();
  }

  close(): void {
    this.database.close();
  }

  recordUsage(receipt: UsageReceipt, recordedAt: Date = new Date()): void {
    const params = receiptParams(randomUUID(), receipt, recordedAt.toISOString());
    this.database.prepare(`
      INSERT INTO usage_receipts (
        id, recorded_at, provider, model, input_tokens, output_tokens,
        audio_seconds, estimated_cost_usd
      ) VALUES (
        @id, @recordedAt, @provider, @model, @inputTokens, @outputTokens,
        @audioSeconds, @estimatedCostUsd
      )
    `).run(params);
  }

  listUsage(): RecordedUsage[] {
    return (this.database.prepare(`
      SELECT recorded_at, provider, model, input_tokens, output_tokens,
        audio_seconds, estimated_cost_usd
      FROM usage_receipts ORDER BY recorded_at, rowid
    `).all() as UsageRow[]).map((row) => ({
      recordedAt: row.recorded_at,
      receipt: receiptFromRow(row),
    }));
  }

  reserveUsage(
    estimatedReceipt: UsageReceipt,
    ceilings: CostCeilings,
    reservedAt: Date = new Date(),
  ): CostReservation {
    const sanitized = sanitizeReceipt(estimatedReceipt);
    const perRequest = finiteNonNegative(ceilings.perRequestUsd, 'perRequestUsd');
    const daily = finiteNonNegative(ceilings.dailyUsd, 'dailyUsd');
    const monthly = finiteNonNegative(ceilings.monthlyUsd, 'monthlyUsd');
    const id = randomUUID();
    const recordedAt = reservedAt.toISOString();
    const period = utcPeriod(reservedAt);

    this.database.transaction(() => {
      const totals = this.database.prepare(`
        SELECT
          COALESCE((SELECT SUM(estimated_cost_usd) FROM usage_receipts
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_reservations
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_request_reservations
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) AS daily,
          COALESCE((SELECT SUM(estimated_cost_usd) FROM usage_receipts
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_reservations
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_request_reservations
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) AS monthly
      `).get(period) as { daily: number; monthly: number };

      if (
        sanitized.estimatedCostUsd > perRequest ||
        totals.daily + sanitized.estimatedCostUsd > daily ||
        totals.monthly + sanitized.estimatedCostUsd > monthly
      ) {
        throw new CostLimitError();
      }

      const params = receiptParams(id, sanitized, recordedAt);
      this.database.prepare(`
        INSERT INTO cost_reservations (
          id, recorded_at, provider, model, input_tokens, output_tokens,
          audio_seconds, estimated_cost_usd, status
        ) VALUES (
          @id, @recordedAt, @provider, @model, @inputTokens, @outputTokens,
          @audioSeconds, @estimatedCostUsd, 'pending'
        )
      `).run(params);
    }).immediate();

    let active = true;
    let providerStarted = false;

    const consumeEstimate = () => {
      if (!active) return;
      this.database.transaction(() => {
        const row = this.database.prepare('SELECT * FROM cost_reservations WHERE id = ?')
          .get(id) as ReservationRow | undefined;
        if (!row) return;
        this.recordUsage(receiptFromRow(row), new Date(row.recorded_at));
        this.database.prepare('DELETE FROM cost_reservations WHERE id = ?').run(id);
      }).immediate();
      active = false;
    };

    return {
      beginProviderInvocation: () => {
        if (!active || providerStarted) return;
        const update = this.database.prepare(`
          UPDATE cost_reservations SET status = 'in_flight'
          WHERE id = ? AND status = 'pending'
        `).run(id);
        if (update.changes !== 1) throw new Error('Cost reservation is unavailable');
        providerStarted = true;
      },
      commit: (receipt) => {
        if (!active) return;
        const actual = sanitizeReceipt(receipt);
        let reservedUsd = 0;
        this.database.transaction(() => {
          const row = this.database.prepare('SELECT * FROM cost_reservations WHERE id = ?')
            .get(id) as ReservationRow | undefined;
          if (!row) throw new Error('Cost reservation is unavailable');
          reservedUsd = row.estimated_cost_usd;
          this.database.prepare('DELETE FROM cost_reservations WHERE id = ?').run(id);
          this.recordUsage(actual, new Date(row.recorded_at));
        }).immediate();
        active = false;
        if (actual.estimatedCostUsd > reservedUsd + Number.EPSILON) {
          throw new UsageExceedsReservationError(reservedUsd, actual.estimatedCostUsd);
        }
      },
      consumeEstimate,
      release: () => {
        if (!active) return;
        if (providerStarted) {
          consumeEstimate();
          return;
        }
        this.database.prepare(`
          DELETE FROM cost_reservations WHERE id = ? AND status = 'pending'
        `).run(id);
        active = false;
      },
    };
  }

  reserveAttempts(
    estimates: readonly AttemptEstimate[],
    ceilings: CostCeilings,
    reservedAt: Date = new Date(),
  ): MultiAttemptCostReservation {
    const sanitized = sanitizeAttemptEstimates(estimates);
    const totalEstimatedCostUsd =
      sanitized.get('primary')!.estimatedCostUsd + sanitized.get('fallback')!.estimatedCostUsd;
    const perRequest = finiteNonNegative(ceilings.perRequestUsd, 'perRequestUsd');
    const daily = finiteNonNegative(ceilings.dailyUsd, 'dailyUsd');
    const monthly = finiteNonNegative(ceilings.monthlyUsd, 'monthlyUsd');
    const id = randomUUID();
    const recordedAt = reservedAt.toISOString();
    const period = utcPeriod(reservedAt);

    this.database.transaction(() => {
      const totals = this.database.prepare(`
        SELECT
          COALESCE((SELECT SUM(estimated_cost_usd) FROM usage_receipts
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_reservations
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_request_reservations
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) AS daily,
          COALESCE((SELECT SUM(estimated_cost_usd) FROM usage_receipts
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_reservations
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_request_reservations
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) AS monthly
      `).get(period) as { daily: number; monthly: number };

      if (
        totalEstimatedCostUsd > perRequest ||
        totals.daily + totalEstimatedCostUsd > daily ||
        totals.monthly + totalEstimatedCostUsd > monthly
      ) {
        throw new CostLimitError();
      }

      this.database.prepare(`
        INSERT INTO cost_request_reservations (
          id, recorded_at, estimated_cost_usd, status
        ) VALUES (?, ?, ?, 'pending')
      `).run(id, recordedAt, totalEstimatedCostUsd);
      const insertAttempt = this.database.prepare(`
        INSERT INTO cost_attempt_reservations (
          request_id, attempt_id, provider, model, input_tokens, output_tokens,
          estimated_cost_usd, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')
      `);
      for (const attemptId of ['primary', 'fallback'] as const) {
        const estimate = sanitized.get(attemptId)!;
        insertAttempt.run(
          id,
          attemptId,
          estimate.provider,
          estimate.model,
          estimate.inputTokens ?? null,
          estimate.outputTokens ?? null,
          estimate.estimatedCostUsd,
        );
      }
    }).immediate();

    let active = true;

    function assertKnownAttempt(
      attemptId: string,
    ): asserts attemptId is AttemptEstimate['attemptId'] {
      if (attemptId !== 'primary' && attemptId !== 'fallback') {
        throw new Error(`Unknown attempt: ${attemptId}`);
      }
    }

    const insertUsage = this.database.prepare(`
      INSERT INTO usage_receipts (
        id, recorded_at, provider, model, input_tokens, output_tokens,
        audio_seconds, estimated_cost_usd
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)
    `);

    return {
      beginAttempt: (attemptId) => {
        assertKnownAttempt(attemptId);
        if (!active) throw new Error('Cost reservation is unavailable');

        this.database.transaction(() => {
          const current = this.database.prepare(`
            SELECT request_id, attempt_id, provider, model, input_tokens, output_tokens,
              estimated_cost_usd, status, '' AS recorded_at
            FROM cost_attempt_reservations WHERE request_id = ? AND attempt_id = ?
          `).get(id, attemptId) as AttemptReservationRow | undefined;
          if (!current) throw new Error('Cost reservation is unavailable');
          if (current.status === 'settled') throw new Error(`${attemptId} already settled`);
          if (current.status === 'in_flight') throw new Error(`${attemptId} already in flight`);

          if (attemptId === 'fallback') {
            const primary = this.database.prepare(`
              SELECT status FROM cost_attempt_reservations
              WHERE request_id = ? AND attempt_id = 'primary'
            `).get(id) as { status: AttemptReservationRow['status'] } | undefined;
            if (primary?.status === 'pending') throw new Error('primary must begin first');
            if (primary?.status !== 'settled') throw new Error('primary must settle before fallback');
          }

          this.database.prepare(`
            UPDATE cost_attempt_reservations SET status = 'in_flight'
            WHERE request_id = ? AND attempt_id = ? AND status = 'pending'
          `).run(id, attemptId);
          this.database.prepare(`
            UPDATE cost_request_reservations SET status = 'in_flight' WHERE id = ?
          `).run(id);
        }).immediate();
      },
      settleAttempt: (settlement) => {
        assertKnownAttempt(settlement.attemptId);
        if (!active) throw new Error('Cost reservation is unavailable');

        let overrun: UsageExceedsReservationError | undefined;
        this.database.transaction(() => {
          const current = this.database.prepare(`
            SELECT attempts.request_id, attempts.attempt_id, attempts.provider, attempts.model,
              attempts.input_tokens, attempts.output_tokens, attempts.estimated_cost_usd,
              attempts.status, requests.recorded_at
            FROM cost_attempt_reservations AS attempts
            JOIN cost_request_reservations AS requests ON requests.id = attempts.request_id
            WHERE attempts.request_id = ? AND attempts.attempt_id = ?
          `).get(id, settlement.attemptId) as AttemptReservationRow | undefined;
          if (!current) throw new Error('Cost reservation is unavailable');
          if (current.status !== 'in_flight') throw new Error(`${settlement.attemptId} is not in flight`);

          const actual = sanitizeReceipt(settlement.receipt ?? receiptFromAttemptRow(current));
          insertUsage.run(
            randomUUID(),
            current.recorded_at,
            actual.provider,
            actual.model,
            actual.inputTokens ?? null,
            actual.outputTokens ?? null,
            actual.estimatedCostUsd,
          );
          this.database.prepare(`
            UPDATE cost_attempt_reservations SET status = 'settled'
            WHERE request_id = ? AND attempt_id = ? AND status = 'in_flight'
          `).run(id, settlement.attemptId);
          this.database.prepare(`
            UPDATE cost_request_reservations
            SET estimated_cost_usd = estimated_cost_usd - ?
            WHERE id = ?
          `).run(current.estimated_cost_usd, id);
          if (actual.estimatedCostUsd > current.estimated_cost_usd + Number.EPSILON) {
            overrun = new UsageExceedsReservationError(
              current.estimated_cost_usd,
              actual.estimatedCostUsd,
            );
          }
        }).immediate();
        if (overrun) throw overrun;
      },
      release: () => {
        if (!active) return;
        this.database.transaction(() => {
          const inFlight = this.database.prepare(`
            SELECT attempts.request_id, attempts.attempt_id, attempts.provider, attempts.model,
              attempts.input_tokens, attempts.output_tokens, attempts.estimated_cost_usd,
              attempts.status, requests.recorded_at
            FROM cost_attempt_reservations AS attempts
            JOIN cost_request_reservations AS requests ON requests.id = attempts.request_id
            WHERE attempts.request_id = ? AND attempts.status = 'in_flight'
            ORDER BY CASE attempts.attempt_id WHEN 'primary' THEN 0 ELSE 1 END
          `).all(id) as AttemptReservationRow[];
          for (const attempt of inFlight) {
            const estimate = receiptFromAttemptRow(attempt);
            insertUsage.run(
              randomUUID(),
              attempt.recorded_at,
              estimate.provider,
              estimate.model,
              estimate.inputTokens ?? null,
              estimate.outputTokens ?? null,
              estimate.estimatedCostUsd,
            );
          }
          this.database.prepare('DELETE FROM cost_request_reservations WHERE id = ?').run(id);
        }).immediate();
        active = false;
      },
    };
  }

  reserveCost(
    estimatedCostUsd: number,
    ceilings: CostCeilings,
    reservedAt: Date = new Date(),
  ): CostReservation {
    return this.reserveUsage(
      { provider: 'openai', model: 'cost-reservation', estimatedCostUsd },
      ceilings,
      reservedAt,
    );
  }
}

export function readCostCeilings(
  environment: Record<string, string | undefined> = process.env,
): CostCeilings {
  const read = (name: string) => {
    const raw = environment[name]?.trim();
    const value = raw === undefined || raw === '' ? Number.NaN : Number(raw);
    if (!Number.isFinite(value) || value < 0) throw new CostConfigurationError(name);
    return value;
  };

  return {
    perRequestUsd: read('TAISA_AI_COST_CEILING_PER_REQUEST_USD'),
    dailyUsd: read('TAISA_AI_COST_CEILING_DAILY_USD'),
    monthlyUsd: read('TAISA_AI_COST_CEILING_MONTHLY_USD'),
  };
}

let defaultLedger: CostLedger | undefined;

function getDefaultLedger(): CostLedger {
  if (!defaultLedger) {
    defaultLedger = new CostLedger({
      databasePath:
        process.env.TAISA_USAGE_LEDGER_PATH?.trim() ||
        path.resolve(process.cwd(), 'taisa-usage-ledger.sqlite'),
    });
  }
  return defaultLedger;
}

export const costLedger: UsageLedger & Pick<CostLedger, 'reserveCost'> = {
  recordUsage: (receipt, recordedAt) => getDefaultLedger().recordUsage(receipt, recordedAt),
  listUsage: () => getDefaultLedger().listUsage(),
  reserveUsage: (receipt, ceilings, reservedAt) =>
    getDefaultLedger().reserveUsage(receipt, ceilings, reservedAt),
  reserveAttempts: (estimates, ceilings, reservedAt) =>
    getDefaultLedger().reserveAttempts(estimates, ceilings, reservedAt),
  reserveCost: (estimatedCostUsd, ceilings, reservedAt) =>
    getDefaultLedger().reserveCost(estimatedCostUsd, ceilings, reservedAt),
};

export function reserveCost(
  estimatedCostUsd: number,
  ceilings: CostCeilings = readCostCeilings(),
): CostReservation {
  return getDefaultLedger().reserveCost(estimatedCostUsd, ceilings);
}

export function reserveUsage(
  estimatedReceipt: UsageReceipt,
  ceilings: CostCeilings = readCostCeilings(),
): CostReservation {
  return getDefaultLedger().reserveUsage(estimatedReceipt, ceilings);
}

export function reserveAttempts(
  estimates: readonly AttemptEstimate[],
  ceilings: CostCeilings = readCostCeilings(),
): MultiAttemptCostReservation {
  return getDefaultLedger().reserveAttempts(estimates, ceilings);
}

export function recordUsage(receipt: UsageReceipt): void {
  getDefaultLedger().recordUsage(receipt);
}

export function closeDefaultCostLedger(): void {
  if (defaultLedger) {
    defaultLedger.close();
    defaultLedger = undefined;
  }
}
