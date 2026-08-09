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
  commit(receipt: UsageReceipt): void;
  release(): void;
}

interface PendingReservation {
  estimatedCostUsd: number;
  reservedAt: Date;
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

function finiteNonNegative(value: number, name: string): number {
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number`);
  }
  return value;
}

function sanitizeReceipt(receipt: UsageReceipt): UsageReceipt {
  const sanitized: UsageReceipt = {
    provider: receipt.provider,
    model: receipt.model,
  } as UsageReceipt;

  if (receipt.inputTokens !== undefined) sanitized.inputTokens = receipt.inputTokens;
  if (receipt.outputTokens !== undefined) sanitized.outputTokens = receipt.outputTokens;
  if (receipt.audioSeconds !== undefined) sanitized.audioSeconds = receipt.audioSeconds;
  sanitized.estimatedCostUsd = finiteNonNegative(
    receipt.estimatedCostUsd,
    'estimatedCostUsd',
  );
  return sanitized;
}

function utcDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function utcMonth(date: Date): string {
  return date.toISOString().slice(0, 7);
}

export class CostLedger {
  private readonly entries: RecordedUsage[] = [];
  private readonly pending = new Map<symbol, PendingReservation>();

  recordUsage(receipt: UsageReceipt, recordedAt: Date = new Date()): void {
    this.entries.push({
      recordedAt: recordedAt.toISOString(),
      receipt: sanitizeReceipt(receipt),
    });
  }

  listUsage(): RecordedUsage[] {
    return this.entries.map((entry) => ({
      recordedAt: entry.recordedAt,
      receipt: { ...entry.receipt },
    }));
  }

  reserveCost(
    estimatedCostUsd: number,
    ceilings: CostCeilings,
    reservedAt: Date = new Date(),
  ): CostReservation {
    const estimated = finiteNonNegative(estimatedCostUsd, 'estimatedCostUsd');
    const perRequest = finiteNonNegative(ceilings.perRequestUsd, 'perRequestUsd');
    const daily = finiteNonNegative(ceilings.dailyUsd, 'dailyUsd');
    const monthly = finiteNonNegative(ceilings.monthlyUsd, 'monthlyUsd');

    const recordedDaily = this.entries
      .filter((entry) => utcDay(new Date(entry.recordedAt)) === utcDay(reservedAt))
      .reduce((sum, entry) => sum + entry.receipt.estimatedCostUsd, 0);
    const recordedMonthly = this.entries
      .filter((entry) => utcMonth(new Date(entry.recordedAt)) === utcMonth(reservedAt))
      .reduce((sum, entry) => sum + entry.receipt.estimatedCostUsd, 0);
    const pendingDaily = [...this.pending.values()]
      .filter((entry) => utcDay(entry.reservedAt) === utcDay(reservedAt))
      .reduce((sum, entry) => sum + entry.estimatedCostUsd, 0);
    const pendingMonthly = [...this.pending.values()]
      .filter((entry) => utcMonth(entry.reservedAt) === utcMonth(reservedAt))
      .reduce((sum, entry) => sum + entry.estimatedCostUsd, 0);

    if (
      estimated > perRequest ||
      recordedDaily + pendingDaily + estimated > daily ||
      recordedMonthly + pendingMonthly + estimated > monthly
    ) {
      throw new CostLimitError();
    }

    const id = Symbol('cost-reservation');
    this.pending.set(id, { estimatedCostUsd: estimated, reservedAt });
    let active = true;

    return {
      commit: (receipt) => {
        if (!active) return;
        active = false;
        this.pending.delete(id);
        this.recordUsage(receipt, reservedAt);
      },
      release: () => {
        if (!active) return;
        active = false;
        this.pending.delete(id);
      },
    };
  }
}

export const costLedger = new CostLedger();

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

export function reserveCost(
  estimatedCostUsd: number,
  ceilings: CostCeilings = readCostCeilings(),
): CostReservation {
  return costLedger.reserveCost(estimatedCostUsd, ceilings);
}

export function recordUsage(receipt: UsageReceipt): void {
  costLedger.recordUsage(receipt);
}
