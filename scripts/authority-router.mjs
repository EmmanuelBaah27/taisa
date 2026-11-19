const AGENT_DECISIONS = new Set([
  "technical-plan",
  "test-selection",
  "branch-mechanics",
  "implementation",
]);

const BAAH_DECISIONS = new Set([
  "product-intent",
  "material-experience",
  "security",
  "privacy",
  "destructive-data",
  "paid-service",
  "difficult-to-reverse",
  "tracer-experience-review",
  "physical-qa",
  "perceptual-qa",
  "ship",
]);

export function selectDecisionOwner({ decision } = {}) {
  if (AGENT_DECISIONS.has(decision)) {
    return { owner: "agent", gate: "continue" };
  }

  if (BAAH_DECISIONS.has(decision)) {
    return { owner: "Baah", gate: "stop-for-explicit-decision" };
  }

  throw new Error(`Unclassified decision: ${decision ?? "missing"}`);
}
