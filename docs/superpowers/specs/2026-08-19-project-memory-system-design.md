# Taisa Project Memory System Design

**Status:** Approved by Baah — 2026-08-20

## Purpose

Taisa already preserves product intent, implementation plans, canonical technical
documentation, QA notes, and Git history. The missing layer is a consistent way to
promote decisions and reusable lessons out of task conversations into durable,
discoverable project memory.

This change makes that promotion part of the normal Taisa workflow. It does not add a
database, external knowledge service, or automated summarisation system.

## Goals

- Give every agent a small, deterministic set of memory sources to read at session start.
- Preserve cross-cutting decisions with their context, alternatives, and consequences.
- Preserve reusable learnings without turning routine activity into documentation noise.
- Close shipped work with the actual outcome, deviations, follow-ups, and merge evidence.
- Keep canonical technical documents authoritative for current system behaviour.
- Make ownership and promotion rules explicit so memory compounds across features.

## Non-goals

- Capturing complete chat transcripts or agent chain-of-thought.
- Replacing scope documents, plans, Linear, Git history, or canonical technical docs.
- Creating a second project-status tracker.
- Retrofitting every historical feature, plan, and decision in the repository.
- Automatically changing accepted architecture from an unreviewed learning.

## Memory hierarchy

Agents use the narrowest authoritative source for each question:

1. `AGENTS.md`, `CLAUDE.md`, `docs/workflow.md`, and the Taisa workflow skill define
   operating rules and mandatory startup.
2. Canonical domain documents such as `docs/architecture.md`, `docs/api.md`, and
   `docs/design-system.md` define how the current system works.
3. `docs/decisions/` explains why consequential cross-cutting choices were made.
4. `docs/learnings.md` records concise, reusable findings that may affect future work.
5. Feature scopes, specifications, plans, QA notes, PRs, and commits retain work-specific
   intent and history.

When sources conflict, current canonical domain documentation describes present
behaviour. A decision record explains the accepted reasoning. A learning is advisory
until promoted into a workflow rule, decision record, or canonical domain document.

## Project memory index

Create `docs/project-memory.md` as the entry point agents read during orientation. It
will explain the hierarchy above and link to:

- canonical product and technical documents;
- accepted decision records;
- the reusable learning log;
- active workflow state;
- feature scopes, plans, and QA notes.

The index is a navigation map, not a duplicate summary of every linked document.

## Decision records

Create `docs/decisions/README.md` and store records as
`docs/decisions/NNNN-short-kebab-title.md`. Numbers are four digits and increase
monotonically. Existing records are never renumbered.

Use a decision record when a choice:

- changes architecture or data ownership;
- establishes a cross-feature platform or design-system rule;
- changes a public/internal interface with multiple consumers;
- creates a durable security, privacy, reliability, or operational constraint;
- supersedes a previous accepted decision.

Do not create one for local implementation details, routine dependency updates, or
choices fully contained within one feature plan.

Each record contains:

- title and status (`Proposed`, `Accepted`, `Superseded`, or `Rejected`);
- date and owners;
- context and decision drivers;
- considered options;
- decision and rationale;
- consequences and follow-ups;
- links to superseded records, scope, plan, PR, or canonical docs.

Baah approval is required to mark a proposed record `Accepted` when the decision changes
product scope, architecture invariants, or a breaking shared contract. Agents may record
already-approved decisions directly as `Accepted` when the approval source is linked.
Superseding a record creates a new record and updates the old record's status and link;
history is not rewritten.

## Reusable learning log

Create `docs/learnings.md` as a compact append-only table with these fields:

| Date | Area | Learning | Evidence | Promoted to |
|---|---|---|---|---|

Areas use a small stable vocabulary: `Product`, `Platform`, `Mobile`, `Backend`,
`Design System`, `AI`, `QA`, and `Workflow`.

A learning belongs here only when it is evidence-backed and likely to influence another
feature, agent, or future decision. Suitable sources include a root-cause fix, repeated
QA failure, platform constraint discovered during implementation, successful reusable
pattern, or a non-obvious toolchain limitation.

Routine actions, preferences stated once without evidence, temporary debugging notes,
and feature-specific status do not belong in the log.

The `Promoted to` field links the canonical destination after a learning becomes a rule,
decision, test, or domain-document update. Promotion does not delete the learning; the
evidence trail remains intact. If later evidence invalidates a learning, append a new row
that corrects it and links the earlier entry instead of silently rewriting history.

## BTS promotion rule

BTS notes remain short, optional explanations in conversation. At the end of a work
session, the agent evaluates each non-routine BTS insight:

- feature-specific context stays in the scope, plan, QA note, or PR;
- reusable evidence becomes a row in `docs/learnings.md`;
- an accepted cross-cutting choice becomes a decision record;
- current-behaviour changes update the relevant canonical domain document;
- an insight may land in more than one destination when each serves a distinct purpose,
  but text should link rather than duplicate long explanations.

Skipping conversational BTS does not skip durable retention. The promotion check still
runs during Review and Ship.

## Work closeout

Every Standard and Full feature scope or plan gains a `Closeout` section during Review.
It contains:

- actual outcome;
- deviations from the approved plan;
- reusable learnings and decision-record links;
- remaining debt or follow-ups;
- canonical documents updated;
- PR URL and merge SHA once shipped.

Quick work records these details in the PR description or final commit when material; it
does not require a new scope or plan solely for closeout.

Closeout is not another approval gate. It is agent-owned housekeeping completed before
the Ship claim and finalized with merge evidence after Ship.

## Agent workflow changes

The Taisa orchestrator will require agents to:

1. Read `docs/project-memory.md` during scoped-task orientation.
2. Check relevant accepted decisions and reusable learnings before scoping or planning.
3. Identify memory destinations while building, without interrupting routine work.
4. Run a memory-promotion check during Review.
5. Complete the work closeout and update the memory index when adding a decision record.
6. Verify links, decision statuses, closeout completeness, and clean diffs for
   documentation/workflow changes.

The human-readable workflow will define the same rules and add the new artifacts to its
document conventions. `CLAUDE.md` will point agents to the project memory index without
duplicating its contents.

## Initial content

The first implementation creates the structure and templates, plus one accepted decision
record documenting why Taisa uses repository-native layered memory instead of chat history
or an external knowledge store. It does not attempt a broad historical backfill.

`docs/learnings.md` starts with instructions and no invented historical learnings. Future
entries must cite concrete evidence.

## Verification

Because this is a documentation/workflow change, verification consists of:

- every referenced path existing;
- all relative Markdown links resolving;
- decision filenames and statuses following the documented convention;
- `docs/workflow.md`, the Taisa orchestrator, `CLAUDE.md`, and the project memory index
  agreeing on startup and promotion behaviour;
- a repository search confirming no contradictory closeout or memory rules;
- a clean, focused diff containing no product-code or dependency changes.

## Acceptance criteria

- Agents have one documented entry point for durable project context.
- Cross-cutting decisions have a standard, reviewable, append-preserving record format.
- Reusable learnings have an evidence-backed log and an explicit promotion lifecycle.
- BTS insights can move from conversation to the correct durable artifact.
- Standard and Full work receives a closeout before Ship.
- Canonical technical docs remain the source of truth for current behaviour.
- The implementation adds no external service and does not backfill unsupported history.
