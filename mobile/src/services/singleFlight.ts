export interface PromiseRef<T> {
  current: Promise<T> | null;
}

/** Installs the lock before invoking work, so two same-tick UI events cannot start two actions. */
export function runSingleFlight<T>(
  ref: PromiseRef<T>,
  work: () => Promise<T>,
): Promise<T> {
  if (ref.current !== null) return ref.current;

  let resolveOperation!: (value: T | PromiseLike<T>) => void;
  let rejectOperation!: (reason?: unknown) => void;
  const operation = new Promise<T>((resolve, reject) => {
    resolveOperation = resolve;
    rejectOperation = reject;
  });
  ref.current = operation;

  try {
    void work().then(resolveOperation, rejectOperation);
  } catch (error) {
    rejectOperation(error);
  }

  // Supplying both handlers ensures lock cleanup never creates an unhandled rejected promise.
  void operation.then(
    () => { if (ref.current === operation) ref.current = null; },
    () => { if (ref.current === operation) ref.current = null; },
  );
  return operation;
}
