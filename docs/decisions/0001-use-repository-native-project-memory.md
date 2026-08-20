# 0001: Use Repository-Native Project Memory

**Status:** Accepted
**Date:** 2026-08-20
**Owners:** Baah + the agent

## Context

Taisa already preserves product intent, implementation plans, canonical technical
documentation, QA notes, and Git history. Context was distributed across those sources,
but agents did not have one deterministic entry point or consistent rules for retaining
cross-cutting decisions and reusable lessons between sessions.

## Decision drivers

- Discoverable from every repository checkout and isolated worktree
- Reviewable through normal diffs, commits, and pull requests
- Available offline without a separate service or account
- Explicit authority for canonical documents that describe current behavior
- Durable reasoning without retaining chat transcripts or private chain-of-thought
- Small enough to remain useful instead of becoming a second status tracker

## Considered options

1. **Depend on chat history.** Convenient inside one conversation, but unreliable across
   new sessions, tools, context compaction, and repository handoffs.
2. **Use an external knowledge service.** Searchable and potentially automated, but adds
   another authority, dependency, permission surface, and synchronization problem.
3. **Use repository-native layered memory.** Adds a small index, decision records,
   evidence-backed learnings, and work closeouts alongside the sources they explain.

## Decision

Taisa will use repository-native layered memory. `docs/project-memory.md` is the routing
index; canonical domain documents remain authoritative for present behavior;
`docs/decisions/` retains accepted reasoning; `docs/learnings.md` retains reusable
evidence; feature artifacts, pull requests, and Git retain work-specific history.

## Consequences

- Every scoped session has a deterministic context entry point.
- Decisions and learnings are reviewed and versioned with the project.
- Agents must promote non-routine findings during Review and complete Standard/Full
  closeouts without duplicating entire source documents.
- Context quality depends on concise maintenance; this design deliberately adds no
  automatic transcript ingestion or broad historical backfill.

## Follow-ups

- Enforce the memory files, startup links, status conventions, and closeout rules in the
  workflow verifier.
- Revisit external indexing only if repository navigation becomes measurably inadequate.

## References

- [Approved project memory system design](../superpowers/specs/2026-08-19-project-memory-system-design.md)
