import assert from "node:assert/strict";
import test from "node:test";

import { proveMattWorkflow } from "../matt-workflow-e2e.mjs";

const completedTracer = (id) => ({
  id,
  status: "done",
  integrated: true,
  evidence: {
    creativeLoop: true,
    functionalLoop: true,
    tdd: true,
    focusedProof: true,
    experienceReview: { owner: "Baah", status: "approved" },
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
    tracers: [completedTracer("tracer-a"), completedTracer("tracer-b")],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      existingCandidates: ["tracer-a"],
      includedCandidates: ["tracer-a", "tracer-b"],
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
    tracerReview: "satisfied",
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
        tracers: [completedTracer("tracer-a")],
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
    tracers: [completedTracer("tracer-a")],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      includedCandidates: ["tracer-a"],
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

test("the end-to-end route requires Baah tracer-review evidence", () => {
  const input = {
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    tracers: [{
      ...completedTracer("tracer-a"),
      evidence: {
        ...completedTracer("tracer-a").evidence,
        experienceReview: undefined,
      },
    }],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      includedCandidates: ["tracer-a"],
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
  };

  assert.throws(() => proveMattWorkflow(input), /experience approval or a reasoned not-applicable/i);
});

test("a documentation-only tracer uses reasoned non-applicable review and Preview evidence", () => {
  const tracer = completedTracer("docs-only");
  tracer.evidence.experienceReview = {
    status: "not-applicable",
    rationale: "Documentation-only tracer has no reviewable product experience.",
  };
  tracer.evidence.previewCheckpoint = {
    status: "not-meaningful",
    rationale: "Documentation-only tracer has no runnable surface.",
  };

  const result = proveMattWorkflow({
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    tracers: [tracer],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      includedCandidates: [],
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

  assert.equal(result.routes.tracerReview, "satisfied");
  assert.equal(result.routes.preview, "publish-cumulative");
});

test("a published tracer cannot bypass Baah experience review", () => {
  const tracer = completedTracer("published-tracer");
  tracer.evidence.experienceReview = {
    status: "not-applicable",
    rationale: "A reason alone cannot bypass review for a published tracer.",
  };

  assert.throws(
    () => proveMattWorkflow({
      tracers: [tracer],
      wholeSpecReview: "pass",
      candidate: { wholeSpecReview: "pass" },
    }),
    /experience approval or a reasoned not-applicable/i,
  );
});

test("the cumulative Preview must include every reviewed integrated tracer", () => {
  const input = {
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    tracers: [completedTracer("tracer-a"), completedTracer("tracer-b")],
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      includedCandidates: ["unrelated-candidate"],
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
  };

  assert.throws(() => proveMattWorkflow(input), /missing reviewed candidate tracer-a/);
});

test("an explicitly reverted or replaced tracer remains accounted for", () => {
  const base = {
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    tracers: [completedTracer("tracer-a"), completedTracer("tracer-b")],
    wholeSpecReview: "pass",
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
  };
  const preview = {
    source: "reviewed-integration-checkpoint",
    previewRevision: "preview-123",
    specRevision: "spec-123",
    tracerRevision: "tracer-123",
    existingCandidates: ["tracer-a", "tracer-b"],
    brokenCandidates: ["tracer-a"],
    includedCandidates: ["tracer-b"],
    proof: { topology: "pass", build: "pass", affectedInteractionSmoke: "pass" },
  };

  assert.equal(proveMattWorkflow({ ...base, preview: { ...preview, action: "revert" } }).routes.preview, "publish-cumulative");
  assert.equal(
    proveMattWorkflow({
      ...base,
      preview: {
        ...preview,
        action: "replace",
        includedCandidates: ["tracer-b", "tracer-a-replacement"],
        replacements: { "tracer-a": "tracer-a-replacement" },
      },
    }).routes.preview,
    "publish-cumulative",
  );

  assert.equal(
    proveMattWorkflow({
      ...base,
      preview: {
        ...preview,
        brokenCandidates: [],
        obsoleteCandidates: ["tracer-a"],
        action: "revert",
      },
    }).routes.preview,
    "publish-cumulative",
  );
});

test("tracer IDs must be present and unique before Preview accounting", () => {
  const base = {
    oneSession: { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 },
    multiSession: {
      workType: "feature",
      clarity: "clear",
      phase: "implementation",
      sessions: "multiple",
    },
    materialDecision: { decision: "material-experience" },
    wholeSpecReview: "pass",
    preview: {
      source: "reviewed-integration-checkpoint",
      previewRevision: "preview-123",
      specRevision: "spec-123",
      tracerRevision: "tracer-123",
      includedCandidates: ["tracer-a"],
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
  };

  assert.throws(
    () => proveMattWorkflow({ ...base, tracers: [{ ...completedTracer("tracer-a"), id: "" }] }),
    /canonical unique IDs/,
  );
  assert.throws(
    () => proveMattWorkflow({ ...base, tracers: [{ ...completedTracer("tracer-a"), id: "   " }] }),
    /canonical unique IDs/,
  );
  assert.throws(
    () => proveMattWorkflow({
      ...base,
      tracers: [completedTracer("tracer-a"), completedTracer("tracer-a")],
    }),
    /canonical unique IDs/,
  );
});
