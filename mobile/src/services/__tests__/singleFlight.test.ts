import { runSingleFlight, type PromiseRef } from '../singleFlight';

describe('single-flight UI action lock', () => {
  test('installs the promise synchronously and reuses it for a rapid second action', async () => {
    const ref: PromiseRef<void> = { current: null };
    let release!: () => void;
    const work = jest.fn(() => new Promise<void>((resolve) => { release = resolve; }));

    const first = runSingleFlight(ref, work);
    const second = runSingleFlight(ref, work);

    expect(ref.current).toBe(first);
    expect(second).toBe(first);
    expect(work).toHaveBeenCalledTimes(1);

    release();
    await first;
    expect(ref.current).toBeNull();
  });

  test('releases the lock after rejection without creating an unhandled derived promise', async () => {
    const ref: PromiseRef<void> = { current: null };
    const failure = new Error('safe failure');

    await expect(runSingleFlight(ref, async () => { throw failure; })).rejects.toBe(failure);
    expect(ref.current).toBeNull();

    await expect(runSingleFlight(ref, async () => undefined)).resolves.toBeUndefined();
  });
});
