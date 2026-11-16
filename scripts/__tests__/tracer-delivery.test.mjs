import assert from "node:assert/strict";
import test from "node:test";

import {
  hasWholeSpecReviewPrerequisite,
  reviewTracer,
  selectReadyTracerTickets,
} from "../tracer-delivery.mjs";

const completeEvidence = {
  creativeLoop: true,
  functionalLoop: true,
  tdd: true,
  focusedProof: true,
  standardsReview: "pass",
  specReview: "pass",
  previewCheckpoint: { status: "published" },
};

test("independent ready work continues while a reviewed tracer waits for feedback", () => {
  const tickets = [
    { id: "T-1", status: "awaiting-experience-review", blockedBy: [] },
    { id: "T-2", status: "todo", blockedBy: [] },
    { id: "T-3", status: "todo", blockedBy: ["T-1"] },
  ];

  assert.deepEqual(selectReadyTracerTickets(tickets), ["T-2"]);
});

test("dependent work waits for its reviewed product decision", () => {
  const tickets = [
    { id: "T-1", status: "awaiting-experience-review", blockedBy: [] },
    { id: "T-2", status: "todo", blockedBy: ["T-1"] },
  ];

  assert.deepEqual(selectReadyTracerTickets(tickets), []);
});

test("a tracer checkpoint requires the complete creative, functional, proof, review, and Preview evidence set", () => {
  assert.deepEqual(
    reviewTracer(completeEvidence),
    { checkpointReady: true, missing: [] },
  );

  const { specReview: _missingSpecReview, ...incompleteEvidence } = completeEvidence;
  assert.deepEqual(
    reviewTracer(incompleteEvidence),
    { checkpointReady: false, missing: ["specReview"] },
  );

  assert.deepEqual(
    reviewTracer({
      ...completeEvidence,
      previewCheckpoint: { status: "not-meaningful", rationale: "   " },
    }),
    { checkpointReady: false, missing: ["previewCheckpoint"] },
  );

  assert.deepEqual(
    reviewTracer({
      ...completeEvidence,
      previewCheckpoint: {
        status: "not-meaningful",
        rationale: "Documentation-only tracer has no runnable surface.",
      },
    }),
    { checkpointReady: true, missing: [] },
  );
});

test("whole-spec review prerequisite binds every completed tracer to its evidence", () => {
  const completeTickets = [
    { id: "T-1", status: "done", evidence: completeEvidence },
    { id: "T-2", status: "done", evidence: completeEvidence },
  ];

  assert.equal(
    hasWholeSpecReviewPrerequisite({ tickets: completeTickets, wholeSpecReview: "pass" }),
    true,
  );
  assert.equal(
    hasWholeSpecReviewPrerequisite({ tickets: completeTickets, wholeSpecReview: "pending" }),
    false,
  );
  assert.equal(
    hasWholeSpecReviewPrerequisite({
      tickets: [...completeTickets, { id: "T-3", status: "todo", evidence: completeEvidence }],
      wholeSpecReview: "pass",
    }),
    false,
  );
  assert.equal(
    hasWholeSpecReviewPrerequisite({
      tickets: [{ id: "T-1", status: "done" }],
      wholeSpecReview: "pass",
    }),
    false,
  );
});
