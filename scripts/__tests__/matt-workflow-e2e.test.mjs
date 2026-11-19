import assert from "node:assert/strict";
import test from "node:test";

import { proveMattWorkflow } from "../matt-workflow-e2e.mjs";

const completedTracer = (id) => ({
  id,
  status: "done",
  evidence: {
    creativeLoop: true,
    functionalLoop: true,
    tdd: true,
    focusedProof: true,
    standardsReview: "pass",
    specReview: "pass",
    previewCheckpoint: { status: "published" },
  },
});

test("the contracted workflow proves every retained route in order", () => {
  const result = proveMattWorkflow({
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    tracers: [completedTracer("APF-81"), completedTracer("APF-82")],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      existingCandidates: ["APF-81"],
      includedCandidates: ["APF-81", "APF-82"],
      proof: { topology: "pass", build: "pass", affectedInteractionSmoke: "pass" },
    },
    retrospective: { finding: "duplicated process" },
    candidate: {
      wholeSpecReview: "pass",
      standardsReview: "pass",
      clean: true,
      exactHead: "candidate-123",
      completeMatrixRevision: "candidate-123",
      baahQa: "pass",
      shipApproval: "approved",
    },
  });

  assert.deepEqual(result.routes, {
    oneSession: "implement",
    multiSession: "to-spec -> to-tickets -> per-ticket implement",
    materialDecision: "stop-for-explicit-decision",
    tracerReview: "pass",
    preview: "publish-cumulative",
    retrospective: "consolidate-or-remove",
    qa: "pass",
    ship: "approved",
  });
  assert.deepEqual(result.sequence, [
    "whole-spec-review",
    "standards-review",
    "clean-candidate-freeze",
    "exact-head-complete-matrix",
    "baah-qa",
    "ship-approval",
  ]);
});

test("candidate freeze fails closed before whole-spec review", () => {
  assert.throws(
    () =>
      proveMattWorkflow({
        oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
        multiSession: {
          workType: "feature",
          clarity: "clear",
          phase: "implementation",
          sessions: "multiple",
        },
        materialDecision: { decision: "material-experience" },
        tracers: [completedTracer("APF-81")],
        wholeSpecReview: "fail",
        preview: {},
        retrospective: { finding: "duplicated process" },
        candidate: {},
      }),
    /whole-spec review/i,
  );
});

test("the complete matrix must prove the frozen exact head", () => {
  const input = {
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    tracers: [completedTracer("APF-81")],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      includedCandidates: ["APF-81"],
      proof: { topology: "pass", build: "pass", affectedInteractionSmoke: "pass" },
    },
    retrospective: { finding: "duplicated process" },
    candidate: {
      wholeSpecReview: "pass",
      standardsReview: "pass",
      clean: true,
      exactHead: "candidate-123",
      completeMatrixRevision: "older-candidate",
      baahQa: "pass",
      shipApproval: "approved",
    },
  };

  assert.throws(() => proveMattWorkflow(input), /exact frozen head/i);
});
