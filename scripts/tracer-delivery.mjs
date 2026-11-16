function indexTickets(tickets) {
  const byId = new Map();

  for (const ticket of tickets) {
    if (!ticket.id || byId.has(ticket.id)) throw new Error("Tracer tickets require unique IDs");
    byId.set(ticket.id, ticket);
  }

  return byId;
}

export function selectReadyTracerTickets(tickets) {
  const byId = indexTickets(tickets);

  return tickets
    .filter((ticket) => ticket.status === "todo")
    .filter((ticket) =>
      (ticket.blockedBy ?? []).every((blockerId) => {
        const blocker = byId.get(blockerId);
        if (!blocker) throw new Error(`Unknown tracer blocker: ${blockerId}`);
        return blocker.status === "done";
      }),
    )
    .map((ticket) => ticket.id);
}

export function reviewTracer(evidence) {
  const required = [
    "creativeLoop",
    "functionalLoop",
    "tdd",
    "focusedProof",
    "standardsReview",
    "specReview",
    "previewCheckpoint",
  ];
  const missing = required.filter((field) => {
    if (["creativeLoop", "functionalLoop", "tdd", "focusedProof"].includes(field)) {
      return evidence[field] !== true;
    }
    if (field === "previewCheckpoint") {
      const checkpoint = evidence[field];
      if (checkpoint?.status === "published") return false;
      return !(
        checkpoint?.status === "not-meaningful" &&
        typeof checkpoint.rationale === "string" &&
        checkpoint.rationale.trim().length > 0
      );
    }
    return evidence[field] !== "pass";
  });

  return { checkpointReady: missing.length === 0, missing };
}

export function hasWholeSpecReviewPrerequisite({ tickets, wholeSpecReview }) {
  return (
    tickets.length > 0 &&
    tickets.every(
      (ticket) => ticket.status === "done" && reviewTracer(ticket.evidence ?? {}).checkpointReady,
    ) &&
    wholeSpecReview === "pass"
  );
}
