const PASS = "pass";

function requireExactRevisions(publication) {
  if (
    !publication.previewRevision?.trim() ||
    !publication.specRevision?.trim() ||
    !publication.tracerRevision?.trim()
  ) {
    throw new Error("Publication requires exact preview, spec, and tracer revisions.");
  }
}

function allowedRemoval(publication, candidate) {
  if (publication.action === "revert") {
    return publication.brokenCandidates?.includes(candidate);
  }

  if (publication.action === "replace") {
    const replacement = publication.replacements?.[candidate];
    return Boolean(replacement && publication.includedCandidates?.includes(replacement));
  }

  return false;
}

export function validatePreviewPublication(publication = {}) {
  if (publication.source !== "reviewed-integration-checkpoint") {
    throw new Error("Canonical publication requires a reviewed integration checkpoint.");
  }

  requireExactRevisions(publication);

  const included = new Set(publication.includedCandidates ?? []);
  for (const candidate of publication.existingCandidates ?? []) {
    if (!included.has(candidate) && !allowedRemoval(publication, candidate)) {
      throw new Error(`Publication would silently remove ${candidate}.`);
    }
  }

  if (
    publication.brokenCandidates?.length &&
    publication.action !== "revert" &&
    publication.action !== "replace"
  ) {
    throw new Error("A broken candidate requires an explicit revert or replacement.");
  }

  const proof = publication.proof ?? {};
  if (
    proof.topology !== PASS ||
    proof.build !== PASS ||
    proof.affectedInteractionSmoke !== PASS
  ) {
    throw new Error(
      "Publication requires topology, build, and affected-interaction smoke proof.",
    );
  }

  if (proof.broadMatrixRepeated) {
    throw new Error(
      "Clean integration must not repeat unaffected broad verification.",
    );
  }

  return {
    ready: true,
    exactRevisions: {
      preview: publication.previewRevision,
      spec: publication.specRevision,
      tracer: publication.tracerRevision,
    },
  };
}
