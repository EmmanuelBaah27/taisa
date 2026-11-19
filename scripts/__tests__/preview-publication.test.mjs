import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { validatePreviewPublication } from "../preview-publication.mjs";

const validPublication = {
  source: "reviewed-integration-checkpoint",
  action: "add",
  previewRevision: "preview-sha",
  specRevision: "spec-sha",
  tracerRevision: "tracer-sha",
  existingCandidates: ["candidate-a"],
  includedCandidates: ["candidate-a", "candidate-b"],
  proof: {
    topology: "pass",
    build: "pass",
    affectedInteractionSmoke: "pass",
    broadMatrixRepeated: false,
  },
};

test("a reviewed additive checkpoint is ready to publish", () => {
  assert.deepEqual(validatePreviewPublication(validPublication), {
    ready: true,
    exactRevisions: {
      preview: "preview-sha",
      spec: "spec-sha",
      tracer: "tracer-sha",
    },
  });
});

test("a local worktree preview is never canonical", () => {
  assert.throws(
    () => validatePreviewPublication({ ...validPublication, source: "local-worktree" }),
    /reviewed integration checkpoint/,
  );
});

test("publication cannot silently remove an existing candidate", () => {
  assert.throws(
    () => validatePreviewPublication({ ...validPublication, includedCandidates: ["candidate-b"] }),
    /silently remove candidate-a/,
  );
});

test("a broken candidate requires an explicit revert or replacement", () => {
  assert.throws(
    () => validatePreviewPublication({ ...validPublication, brokenCandidates: ["candidate-a"] }),
    /explicit revert or replacement/,
  );
  assert.equal(
    validatePreviewPublication({
      ...validPublication,
      action: "replace",
      brokenCandidates: ["candidate-a"],
      replacements: { "candidate-a": "candidate-b" },
      includedCandidates: ["candidate-b"],
    }).ready,
    true,
  );
});

test("an obsolete candidate may be explicitly reverted", () => {
  const publication = {
    ...validPublication,
    existingCandidates: ["candidate-a", "candidate-b"],
    obsoleteCandidates: ["candidate-a"],
    includedCandidates: ["candidate-b"],
    action: "revert",
  };

  assert.equal(validatePreviewPublication(publication).ready, true);
});

test("a replacement must be included in the cumulative publication", () => {
  assert.throws(
    () => validatePreviewPublication({
      ...validPublication,
      action: "replace",
      brokenCandidates: ["candidate-a"],
      replacements: { "candidate-a": "candidate-b" },
      includedCandidates: [],
    }),
    /included replacement for broken candidate-a/,
  );

  assert.equal(
    validatePreviewPublication({
      ...validPublication,
      action: "replace",
      brokenCandidates: ["candidate-a"],
      replacements: { "candidate-a": "candidate-b" },
      includedCandidates: ["candidate-b"],
    }).ready,
    true,
  );
});

test("a broken candidate cannot remain in the cumulative publication", () => {
  assert.throws(
    () => validatePreviewPublication({
      ...validPublication,
      action: "replace",
      brokenCandidates: ["candidate-a"],
      replacements: { "candidate-a": "candidate-b" },
      includedCandidates: ["candidate-a", "candidate-b"],
    }),
    /broken candidate-a remains included/,
  );

  assert.throws(
    () => validatePreviewPublication({
      ...validPublication,
      action: "replace",
      brokenCandidates: ["candidate-a"],
      replacements: { "other-candidate": "candidate-b" },
      includedCandidates: ["candidate-b"],
    }),
    /replacement for broken candidate-a/,
  );
});

test("publication requires exact revisions and focused integration proof", () => {
  for (const field of ["previewRevision", "specRevision", "tracerRevision"]) {
    assert.throws(
      () => validatePreviewPublication({ ...validPublication, [field]: "" }),
      /exact preview, spec, and tracer revisions/,
    );
  }

  assert.throws(
    () => validatePreviewPublication({
      ...validPublication,
      proof: { ...validPublication.proof, affectedInteractionSmoke: "pending" },
    }),
    /topology, build, and affected-interaction smoke proof/,
  );
});

test("clean integration does not repeat unaffected broad verification", () => {
  assert.throws(
    () => validatePreviewPublication({
      ...validPublication,
      proof: { ...validPublication.proof, broadMatrixRepeated: true },
    }),
    /unaffected broad verification/,
  );
});

test("the workflow documents the cumulative Preview contract and removal condition", () => {
  const workflow = readFileSync("docs/workflow.md", "utf8");
  assert.match(workflow, /local worktree previews are non-canonical/i);
  assert.match(workflow, /reviewed integration-branch checkpoint/i);
  assert.match(workflow, /exact Preview, spec, and tracer revisions/i);
  assert.match(workflow, /explicitly reverted or replaced/i);
  assert.match(
    workflow,
    /main can provide the same stable cumulative product[^.]*canonical Preview extension can be removed/i,
  );
});
