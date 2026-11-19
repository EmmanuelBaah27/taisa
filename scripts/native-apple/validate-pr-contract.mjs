const allowedRisks = new Set([
  'logic',
  'ui',
  'network',
  'device',
  'data',
  'security',
  'workflow',
  'release',
]);

export function validatePullRequestContract({ body, detectedRisks = [], headSha = '' }) {
  const errors = [];
  const tracers = [...new Set(body.match(/\bAPF-\d+\b/g) ?? [])];
  const tracer = tracers.length === 1 ? tracers[0] : null;
  if (tracers.length !== 1) errors.push('Pull request must link exactly one APF Linear tracer.');

  const outcome = body.match(/## Reviewable outcome\s+([\s\S]*?)(?=\n## |$)/i)?.[1]?.trim() ?? '';
  if (!outcome || /Describe the one result/i.test(outcome)) {
    errors.push('Pull request must declare one reviewable outcome.');
  }

  const declaredRisks = new Set(
    [...body.matchAll(/^- \[[xX]\]\s+([a-z-]+)\s*$/gm)]
      .map((match) => match[1])
      .filter((risk) => allowedRisks.has(risk)),
  );
  if (declaredRisks.size === 0) errors.push('Pull request must declare at least one risk.');

  for (const risk of detectedRisks) {
    if (allowedRisks.has(risk) && !declaredRisks.has(risk)) {
      errors.push(`Detected risk is not declared: ${risk}.`);
    }
  }

  if (declaredRisks.has('device')) {
    const evidence = body.match(/## Device QA evidence\s+([\s\S]*?)(?=\n## |$)/i)?.[1]?.trim() ?? '';
    for (const field of ['device', 'operating system', 'behavior', 'result', 'exact commit']) {
      if (!new RegExp(`${field}:\\s*\\S+`, 'i').test(evidence)) {
        errors.push(`Device QA evidence must include ${field}.`);
      }
    }
    if (headSha && !evidence.includes(headSha)) {
      errors.push('Device QA evidence must reference the exact pull-request commit.');
    }
  }

  return { declaredRisks: [...declaredRisks].sort(), errors, tracer };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const body = process.env.PR_BODY ?? '';
  const detectedRisks = (process.env.DETECTED_RISKS ?? '').split(',').filter(Boolean);
  const mode = process.env.PR_CONTRACT_MODE ?? 'enforce';
  const result = validatePullRequestContract({
    body,
    detectedRisks,
    headSha: process.env.PR_HEAD_SHA ?? '',
  });
  console.log(JSON.stringify(result));
  if (result.errors.length > 0) {
    for (const error of result.errors) console.error(error);
    if (mode === 'enforce') process.exitCode = 1;
  }
}
