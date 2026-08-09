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

export interface UsageLedger {
  recordUsage(receipt: UsageReceipt, recordedAt?: Date): void;
  listUsage(): RecordedUsage[];
  reserveUsage(
    estimatedReceipt: UsageReceipt,
    ceilings: CostCeilings,
    reservedAt?: Date,
  ): CostReservation;
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
      CREATE INDEX IF NOT EXISTS idx_usage_receipts_recorded_at
        ON usage_receipts(recorded_at);
      CREATE INDEX IF NOT EXISTS idx_cost_reservations_recorded_at
        ON cost_reservations(recorded_at);
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
            WHERE recorded_at >= @dayStart AND recorded_at < @dayEnd), 0) AS daily,
          COALESCE((SELECT SUM(estimated_cost_usd) FROM usage_receipts
            WHERE recorded_at >= @monthStart AND recorded_at < @monthEnd), 0) +
          COALESCE((SELECT SUM(estimated_cost_usd) FROM cost_reservations
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

export function recordUsage(receipt: UsageReceipt): void {
  getDefaultLedger().recordUsage(receipt);
}
