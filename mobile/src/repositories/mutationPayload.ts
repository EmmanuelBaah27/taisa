export function toDatabaseMutationPayload(
  bindings: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(bindings)
      .filter(([key]) => key !== '$idempotencyId')
      .map(([key, value]) => [key.replace(/^[$:@]/, ''), value ?? null]),
  );
}
