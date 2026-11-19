import { selectDecisionOwner } from "./authority-router.mjs";
import { selectMattRoute } from "./matt-workflow-router.mjs";
import { validatePreviewPublication } from "./preview-publication.mjs";
import { routeRetrospectiveFinding } from "./retrospective-router.mjs";
import { hasWholeSpecReviewPrerequisite } from "./tracer-delivery.mjs";

export function proveMattWorkflow(input = {}) {
  const candidate = input.candidate ?? {};
  if (
    !hasWholeSpecReviewPrerequisite({
      tickets: input.tracers ?? [],
      wholeSpecReview: input.wholeSpecReview,
    }) ||
    candidate.wholeSpecReview !== "pass"
  ) {
    throw new Error("A passing whole-spec review must precede candidate freeze.");
  }

  if (candidate.standardsReview !== "pass") {
    throw new Error("A passing Standards review must precede candidate freeze.");
  }
  if (!candidate.clean || !candidate.exactHead?.trim()) {
    throw new Error("Candidate freeze requires a clean exact head.");
  }
  if (candidate.completeMatrixRevision !== candidate.exactHead) {
    throw new Error("The complete matrix must prove the exact frozen head.");
  }
  if (candidate.baahQa !== "pass") {
    throw new Error("Ship requires passing Baah QA.");
  }
  if (candidate.shipApproval !== "approved") {
    throw new Error("Ship requires explicit approval.");
  }

  const preview = validatePreviewPublication(input.preview);
  const decision = selectDecisionOwner(input.materialDecision);
  const retrospective = routeRetrospectiveFinding(input.retrospective);

  return {
    routes: {
      oneSession: selectMattRoute(input.oneSession),
      multiSession: selectMattRoute(input.multiSession),
      materialDecision: decision.gate,
      tracerReview: "pass",
      preview: preview.ready ? "publish-cumulative" : "blocked",
      retrospective: retrospective.evidence,
      qa: candidate.baahQa,
      ship: candidate.shipApproval,
    },
    sequence: [
      "whole-spec-review",
      "standards-review",
      "clean-candidate-freeze",
      "exact-head-complete-matrix",
      "baah-qa",
      "ship-approval",
    ],
  };
}
