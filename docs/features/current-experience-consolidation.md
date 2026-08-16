# Current Experience Consolidation

**Track:** Platform + Product
**Tier:** Full
**Status:** Scope agreed; design specification awaiting review

## What is it?

Consolidate Taisa's approved local-first platform, Chats experience, chat input states, and evolving design system into one canonical development line. Opening the app from the maintained worktree must show the current Taisa experience rather than the legacy build. Future screen-by-screen Product work must extend this same line, with its design-system layer maintained alongside the screens that consume it.

## Why now?

Substantial approved work currently lives in divergent branches and worktrees based on the same old `main`. Running the primary documentation worktree therefore launches an older app, and design-system changes can drift away from the latest Product implementation. Building another screen before reconciliation would increase conflicts and make it harder to prove which behavior is canonical.

## Acceptance criteria

- [ ] One named integration branch and worktree is documented as the only active runtime for ongoing Product work.
- [ ] The integration baseline preserves the local-first platform without accepting inverse changes that delete its platform capabilities.
- [ ] The Chats list and thread experience are reconciled onto that baseline.
- [ ] The chat input-state behavior is reconciled onto the same baseline.
- [ ] Every uncommitted design-system change is inventoried, classified, and either preserved on the integration branch or explicitly rejected by Baah.
- [ ] Opening the maintained runtime shows the current app experience, not the legacy Logs/journaling build.
- [ ] The design system is maintained inside the latest Product branch and documented in `docs/design-system.md`; no separate long-lived design-system branch is treated as authoritative.
- [ ] Existing user changes and unique commits remain recoverable throughout consolidation.
- [ ] Platform, shared, mobile logic, and mobile UI verification pass before the integration branch is proposed for Ship.
- [ ] Only after canonical `main` contains the verified result may accounted-for branches and disposable worktrees be removed.
- [ ] The Chats-to-thread expanding-card transition is planned from the consolidated baseline rather than added independently to a stale branch.

## Platform dependencies

The approved local-first platform branch is the candidate foundation. Consolidation must preserve its device-local database, conversation repositories, context and memory domain logic, coaching gateway contract, privacy boundaries, and test coverage unless a separately approved scope explicitly changes them.

## Out of scope

- Redesigning screens beyond the already approved Chats presentation
- Adding new coaching, memory, authentication, sync, or backend behavior
- Deleting branches or worktrees before their commits and uncommitted files are accounted for
- Force-pushing, rewriting shared history, or resolving conflicts by selecting an entire branch wholesale
- Implementing the expanding-card transition before the consolidated runtime is verified
