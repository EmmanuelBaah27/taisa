# SwiftUI Functional Home Design

**Date:** 2026-10-07
**Status:** Approved by Baah on 2026-10-07
**Tier:** Full
**Track:** Platform + Product
**Scope:** `docs/features/swiftui-functional-home.md`
**Design handoff:** `docs/features/swiftui-functional-home-design-handoff.md`

## Outcome

Taisa's shipped native foundation becomes a real Product client by replacing the ordinary foundation-diagnostics landing screen with a native app shell and functional Home destination. Home reads recent conversations, active goals, and open actions from the encrypted local store, renders explicit native states, and establishes stable seams for later navigation and redesign.

The slice optimizes for functional progress. It uses standard SwiftUI structure and interactions, carries only minimal Taisa identity, and does not attempt to reproduce the React Native interface. Page redesign happens after the page works. Reusable design-system components are extracted only when a redesigned pattern is proven, not in anticipation of future pages.

This design supersedes earlier Product-slice assumptions that require iOS 17 compatibility, pixel or visual parity with React Native, or a comprehensive design-system migration before native Product work. It does not supersede the native privacy, storage, recovery, signing, or verification guarantees already shipped.

## Product contract

The initial Home surface contains three ordered sections:

1. **Recent conversations** — locally stored conversations ordered by most recently updated first.
2. **Active goals** — locally stored goals whose status is active, ordered by most recently updated first.
3. **Open actions** — locally stored actions whose status is open, with dated actions ordered by due date and remaining items ordered deterministically afterward.

The read model returns bounded collections suitable for a Home overview rather than unbounded history. Exact limits are named constants in the Product query contract and tested. The implementation plan chooses conservative initial limits based on native layout verification rather than embedding unexplained literals in views.

No AI-generated summary, insight ranking, remote fetch, voice entry, coaching prompt, or speculative recommendation appears in this slice.

## Architecture

SwiftUI views render an explicit Home state and emit intents. A main-actor observable model coordinates one Product query protocol. A storage adapter performs local reads through the encrypted store. Neither SwiftUI nor the feature model imports GRDB or knows table names.

```text
HomeView
  → HomeModel (@Observable, @MainActor)
    → HomeQuerying
      → encrypted-store adapter
        → bounded repository/read queries
          → SQLCipher / GRDB
```

The core contracts are:

- `HomeSnapshot` — immutable, sendable recent-conversation, active-goal, and open-action summaries.
- `HomeQuerying` — async, cancellable loading of one coherent snapshot.
- `HomeState` — idle/loading/content/empty/failure, with refresh represented without discarding already visible content.
- `HomeIntent` — retry, refresh, recovery, and typed future-navigation intents.
- `HomeModel` — owns single-flight loading, stale-result rejection, state transitions, and content-free error mapping.

The implementation may place the feature contracts and model in a focused Swift package target if that materially improves testing without slowing delivery. It must not create a generic architecture framework or dependency-injection system for one page.

## Data boundary

Existing repositories expose entity-by-ID CRUD. Home needs new bounded collection reads. Those reads belong below the Product model and above raw SQL:

- recent conversations by `updated_at_ms` descending with stable ID tie-breaking;
- active goals filtered by status and ordered by `updated_at_ms` descending with stable ID tie-breaking;
- open actions filtered by status, ordering non-null `due_at_ms` first, then stable timestamps and IDs.

The Home adapter reads from the local encrypted store only. CloudKit state cannot block or redefine Home content. If a coherent single snapshot requires one database read transaction, the storage boundary provides it; the view does not merge independently timed repository responses.

Read failures become typed, content-free Product failures. Home never responds to an unknown read failure by generating a replacement key, recreating the database, clearing records, or falling back to fixture content.

## App shell and navigation

`TaisaApp` stops presenting `FoundationRootView` as the ordinary Product root. The production shell owns native destination selection and a navigation stack for Home. Diagnostics and preview catalog routes remain restricted to their existing development identities.

This slice establishes typed navigation intents for conversations, goals, actions, recovery, and settings. Only destinations with existing honest behavior are presented. Future tabs or detail pages are not filled with misleading placeholders merely to simulate a complete application.

The shell remains small. It selects destinations and supplies dependencies; it does not contain Home queries, business rules, visual tokens, or storage recovery logic.

## Native-first presentation

Home uses the current iOS visual language through standard SwiftUI components. System navigation, bars, scrolling, row interaction, focus, selection, Dynamic Type, materials, spacing, and accessibility behavior are preferred over custom substitutes.

Custom visual work is intentionally constrained:

- a system tint or existing semantic Taisa accent may establish identity;
- system typography and semantic colors are the default;
- `TaisaText` and `TaisaButton` are reused only where their existing contracts fit naturally;
- feature rows stay feature-local during the functional pass;
- custom glass, shaders, navigation chrome, card systems, and bespoke motion are deferred.

Native-first does not prohibit later redesign. It preserves the native interaction substrate while the redesigned content hierarchy and presentation evolve above it.

## Render states

Home has explicit states:

- **Loading:** native progress treatment with no false content.
- **Empty:** clear explanation that no local conversations, active goals, or open actions exist; recovery access remains available where appropriate.
- **Content:** each nonempty section renders independently; an empty section uses a quiet section-level explanation rather than disappearing ambiguously.
- **Refreshing:** existing content remains visible while a single local reload runs.
- **Recoverable failure:** content-free explanation with Retry and access to the existing recovery route; no destructive automatic action.

If previously loaded content exists and refresh fails, Home preserves that content and surfaces a non-destructive failure indication. A failed newer request cannot be overwritten by an older completion.

## Accessibility and adaptive layout

The baseline target is iOS/iPadOS 26 or later. The app is iPhone-first but structurally adaptable:

- native containers respond to available width and size class;
- the page avoids fixed device widths and hard-coded phone geometry;
- readable content may use a maximum line length or content width at the composition layer;
- native list, focus, keyboard, pointer, sheet, and toolbar behavior remain available on iPad;
- no bespoke iPad information architecture is required in this slice.

Dynamic Type, VoiceOver, increased contrast, Reduce Motion, and reduced transparency are tested as behavioral requirements. Essential labels wrap rather than truncate, section headings expose semantic traits, and state is never communicated by color alone.

## Design-system evolution

The current `TaisaDesignSystem` package is a minimal implemented foundation, not a requirement to wrap every SwiftUI control. This slice follows these rules:

1. Prefer the native component directly.
2. Apply an existing semantic Taisa style only when it adds real identity or consistency.
3. Keep one-page presentation patterns feature-local.
4. Extract into `TaisaDesignSystem` only after reuse is demonstrated or a stable cross-page contract is approved.
5. Update component documentation, previews, and tests in the same change that modifies an implemented shared contract.

The later Home redesign may replace feature-local presentation without changing `HomeSnapshot`, `HomeQuerying`, or the shell's typed navigation seams.

## Privacy and failure handling

Home displays private local content but never writes titles, summaries, counts tied to identifiers, or failure payloads to logs, metrics, screenshots, build evidence, or diagnostics. Preview and tests use synthetic data only.

Store-open, migration, key, integrity, and recovery failures remain owned by the shipped storage/recovery foundation. Home maps them to a small safe state and routes to recovery when allowed; it does not duplicate recovery decisions.

Cancellation, rapid refresh, scene transitions, and repeated retries are expected. Query and model behavior must be idempotent and bounded.

## Verification

The implementation plan must include:

- storage tests for ordering, filtering, bounds, stable tie-breaking, coherent reads, and typed failure behavior;
- model tests for loading, empty, content, refresh, stale-result rejection, retry, and failure-with-existing-content;
- SwiftUI preview/catalog scenarios for every visible state using synthetic data and denied external transport;
- UI tests proving ordinary launch reaches Home and development diagnostics remain isolated;
- accessibility verification for headings, traversal, actions, Dynamic Type, contrast, Reduce Motion, and reduced transparency;
- iPhone and iPad layout verification;
- complete native package, app-target, isolation, and workflow checks;
- exact signed-device QA before Ship.

The implementation must not claim visual redesign completion. Device QA at this stage signs off native interaction quality, readability, correctness, privacy, and adaptability.

## Program reconciliation

Before implementation planning is approved, canonical native-program documents must reflect:

- iOS/iPadOS 26+ as the Product baseline;
- native-first function rather than React Native visual parity;
- vertical Product slices beginning now that their concrete dependencies are available;
- page-level redesign after functional completion;
- implementation-first shared-component documentation rather than speculative catalog expansion;
- current shipped and Review + QA status of native foundation work.

Historical scopes and plans retain their record of earlier decisions but must not override this approved direction.

## Out of scope

- Final Home art direction or page redesign.
- Voice capture, transcription, streaming coaching, or audio-session UI.
- AI-generated Home summaries or recommendations.
- Full destination implementations for Chats, conversations, Goals, Actions, Account, or Settings.
- Automatic CloudKit activation or paid-capability closure.
- Importing React Native data or retiring the React Native client.
- A comprehensive component library, custom navigation system, or generic app architecture framework.
- Bespoke iPad layout or multitasking optimization beyond structural adaptability.

## Approval gates

1. **Design:** Baah approves this written design and handoff.
2. **Plan:** a detailed implementation plan identifies exact files, query contracts, tests, document reconciliation, and verification commands.
3. **Build:** Product implementation begins only after Plan approval.
4. **Ship:** automated checks, exact signed iPhone/iPad QA, and explicit Baah approval.
