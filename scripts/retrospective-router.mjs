const AUTONOMOUS_FINDINGS = new Map([
  ["mechanical failure", "check-or-automation"],
  ["navigation cost", "pointer-or-tool"],
  ["judgment failure", "review-standard"],
  ["duplicated process", "consolidate-or-remove"],
  ["no recurring waste", "explicit-no-change"],
]);

const MATERIAL_AREAS = new Set([
  "authority",
  "privacy",
  "security",
  "verification-coverage",
  "preview",
  "meaningful-cost",
  "ship",
]);

export function routeRetrospectiveFinding({ finding, area } = {}) {
  if (MATERIAL_AREAS.has(area)) {
    return {
      owner: "Baah",
      gate: "stop-for-explicit-decision",
      evidence: "material-redesign-proposal",
    };
  }

  const evidence = AUTONOMOUS_FINDINGS.get(finding);
  if (evidence) {
    return { owner: "agent", gate: "continue", evidence };
  }

  throw new Error(
    `Unclassified retrospective finding: ${finding ?? "missing"}`,
  );
}
