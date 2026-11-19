import { selectDecisionOwner } from "./authority-router.mjs";
import { selectMattRoute } from "./matt-workflow-router.mjs";
import { validatePreviewPublication } from "./preview-publication.mjs";
import { routeRetrospectiveFinding } from "./retrospective-router.mjs";
import {
  hasSatisfiedTracerExperienceReview,
  hasWholeSpecReviewPrerequisite,
} from "./tracer-delivery.mjs";

export function proveMattWorkflow(input = {}) {
  const candidate = input.candidate ?? {};
  const tracers = input.tracers ?? [];
  if (
    tracers.length === 0 ||
    !tracers.every((tracer) => hasSatisfiedTracerExperienceReview(tracer.evidence))
  ) {
    throw new Error(
      "Each tracer requires Baah experience approval or a reasoned not-applicable state.",
    );
  }
  if (
    !hasWholeSpecReviewPrerequisite({
      tickets: tracers,
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

  const preview = validatePreviewPublication(input.preview, {
    requiredCandidates: tracers
      .filter((tracer) => tracer.evidence?.previewCheckpoint?.status === "published")
      .map((tracer) => tracer.id),
  });
  const decision = selectDecisionOwner(input.materialDecision);
  const tracerReview = selectDecisionOwner({ decision: "tracer-experience-review" });
  if (tracerReview.owner !== "Baah") {
    throw new Error("Tracer experience review must remain Baah-owned.");
  }
  const retrospective = routeRetrospectiveFinding(input.retrospective);

  return {
    routes: {
      oneSession: selectMattRoute(input.oneSession),
      multiSession: selectMattRoute(input.multiSession),
      materialDecision: decision.gate,
      tracerReview: "satisfied",
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
