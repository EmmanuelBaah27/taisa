# Taisa Decision Records

Decision records preserve why consequential, cross-cutting choices were accepted. They
supplement canonical domain documentation; they do not replace its description of
present behavior.

## When to create a record

Create a record when a choice changes architecture or data ownership, establishes a
cross-feature platform or design-system rule, changes an interface with multiple
consumers, or creates a durable security, privacy, reliability, or operational
constraint. Do not create one for routine dependencies, local implementation details,
or choices contained entirely within one feature plan.

## Naming and status

- Name records `NNNN-short-kebab-title.md`.
- Use four-digit numbers that increase monotonically. Never renumber existing records.
- Valid statuses are `Proposed`, `Accepted`, `Superseded`, and `Rejected`.
- Baah approves acceptance when a decision changes product scope, architecture
  invariants, or a breaking shared contract.
- The agent may record an already-approved decision as `Accepted` when the approval
  source is linked.
- Superseding a decision creates a new record and updates the old record with the new
  status and link. Never rewrite the original reasoning out of history.

## Records

- [0001: Use repository-native project memory](0001-use-repository-native-project-memory.md)

## Template

```markdown
# NNNN: Decision title

**Status:** Proposed
**Date:** YYYY-MM-DD
**Owners:** Baah + the agent

## Context
## Decision drivers
## Considered options
## Decision
## Consequences
## Follow-ups
## References
```
