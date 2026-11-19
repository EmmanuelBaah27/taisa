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
  const removable = new Set([
    ...(publication.brokenCandidates ?? []),
    ...(publication.obsoleteCandidates ?? []),
  ]);
  if (!removable.has(candidate)) return false;

  if (publication.action === "revert") {
    return true;
  }

  if (publication.action === "replace") {
    const replacement = publication.replacements?.[candidate];
    return Boolean(replacement && publication.includedCandidates?.includes(replacement));
  }

  return false;
}

export function validatePreviewPublication(publication = {}, { requiredCandidates = [] } = {}) {
  if (publication.source !== "reviewed-integration-checkpoint") {
    throw new Error("Canonical publication requires a reviewed integration checkpoint.");
  }

  requireExactRevisions(publication);

  const included = new Set(publication.includedCandidates ?? []);
  const removals = [
    ...(publication.brokenCandidates ?? []).map((candidate) => ({ candidate, kind: "broken" })),
    ...(publication.obsoleteCandidates ?? []).map((candidate) => ({ candidate, kind: "obsolete" })),
  ];
  for (const candidate of requiredCandidates) {
    if (!included.has(candidate) && !allowedRemoval(publication, candidate)) {
      throw new Error(`Publication is missing reviewed candidate ${candidate}.`);
    }
  }
  if (
    removals.length &&
    publication.action !== "revert" &&
    publication.action !== "replace"
  ) {
    throw new Error("A broken or obsolete candidate requires an explicit revert or replacement.");
  }

  for (const { candidate, kind } of removals) {
    if (included.has(candidate)) {
      throw new Error(`The ${kind} ${candidate} remains included.`);
    }
    if (publication.action === "replace" && !allowedRemoval(publication, candidate)) {
      throw new Error(`Publication requires an included replacement for ${kind} ${candidate}.`);
    }
  }

  for (const candidate of publication.existingCandidates ?? []) {
    if (!included.has(candidate) && !allowedRemoval(publication, candidate)) {
      throw new Error(`Publication would silently remove ${candidate}.`);
    }
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
