# SwiftUI Functional Home

**Track:** Platform + Product
**Tier:** Full
**Status:** Review + QA

---

## What is it?

Deliver Taisa's first functional Product vertical slice in the native SwiftUI client: the production app shell and a Home destination backed by the encrypted native store. The slice replaces the foundation diagnostic screen as the ordinary app entry point and proves that shipped native infrastructure can support real Product UI.

This is a functionality-first build. It uses standard SwiftUI navigation, controls, lists, loading behavior, and accessibility with only minimal Taisa identity. The page is deliberately structured for later redesign without requiring its data flow, navigation contract, or state ownership to be rebuilt.

## Why now?

The native app foundation and encrypted local storage/recovery are already merged into `origin/main`. Product work can now begin, but the current repositories expose entity-by-ID CRUD rather than the ordered collection and summary reads Home requires. Completing one real vertical slice will close that platform gap, establish the native Product composition pattern, and let later pages move faster without prematurely designing a broad component library.

## Acceptance criteria

- [x] Launching the ordinary native Taisa app opens a functional Home destination rather than the foundation diagnostics screen.
- [x] Home reads its content from the encrypted native store through a Product-facing query boundary; production UI does not depend on fixtures or hard-coded sample content.
- [x] A new empty store presents a clear native empty state without error-looking placeholders.
- [x] When local data exists, Home presents recent conversations, active goals, and open actions in deterministic order and exposes typed navigation intents for later destinations.
- [x] Loading, empty, populated, refreshing, retryable failure, and recovery-required states are distinguishable and testable without exposing private content.
- [x] A failed store read preserves the local database and offers a safe retry or recovery route.
- [x] Automated simulator coverage exercises iPhone launch, Accessibility XXXL, iPad layout, retry, and recovery reachability.
- [x] Standard SwiftUI navigation and interactions supply the platform behavior; page composition owns the temporary layout.
- [x] The native target and package baseline are iOS/iPadOS 26 or later.
- [x] The React Native client remains intact; this slice does not cut over production or import its on-device data.
- [ ] The exact signed candidate passes the applicable iPhone and iPad device matrix before Ship.

## Platform dependencies

- [x] Shipped Swift native app foundation, deterministic project generation, build identity, preview isolation, and signed-build evidence.
- [x] Merged encrypted native store, recovery-key flow, repositories, and atomic export/restore.
- [ ] Add the ordered collection and summary query contracts required by Home without exposing GRDB details to Product views.
- [ ] Reconcile the native rebuild documents with the approved iOS 26+, native-first, functionality-before-redesign direction before implementation planning.
- [ ] Keep voice-specific UI outside this slice until the native audio and conversation-streaming foundation completes its Ship gate.

## Out of scope

- Final Home visual design, bespoke motion, custom glass effects, or pixel parity with React Native.
- Building a comprehensive design-system component catalog before Product needs prove it.
- Voice recording, transcription, coaching-response streaming, or the final Conversation experience.
- Full Chats, Goals, Account, Settings, or onboarding journeys beyond navigation boundaries needed to keep Home actions honest.
- Activating CloudKit, completing automatic cross-device synchronization, or requiring paid Apple Developer capabilities.
- Importing React Native SQLite, Keychain, settings, recordings, or history into the native store.
- Retiring or deleting the React Native client, its worktrees, or its recoverable Git history.
- Bespoke iPad information architecture; the slice must remain adaptable and usable in an iPad window.

## Closeout

Implemented boundary: `HomeView → HomeModel → HomeClient → HomeQuery → TaisaStore`. Home presentation rows remain feature-local because their redesign and reuse have not yet been proven. Temporary visuals are standard SwiftUI `NavigationStack`, `List`, `Section`, `ContentUnavailableView`, toolbar, refresh, button, label, and progress controls.

Ship remains blocked on review, exact signed-build integration into `preview/taisa`, and Baah's iPhone/iPad device-matrix approval.
